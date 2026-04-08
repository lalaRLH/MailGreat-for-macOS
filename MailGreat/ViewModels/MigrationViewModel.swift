import Foundation
import SwiftUI

/// The steps in the migration wizard.
enum MigrationStep: Int, CaseIterable, Identifiable {
    case welcome
    case sourceAccount
    case destinationAccount
    case folderMapping
    case migration
    case completion

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .sourceAccount: return "Source"
        case .destinationAccount: return "Destination"
        case .folderMapping: return "Folders"
        case .migration: return "Migrate"
        case .completion: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .welcome: return "hand.wave.fill"
        case .sourceAccount: return "arrow.right.doc.on.clipboard"
        case .destinationAccount: return "arrow.left.doc.on.clipboard"
        case .folderMapping: return "folder.badge.gearshape"
        case .migration: return "arrow.triangle.2.circlepath"
        case .completion: return "checkmark.seal.fill"
        }
    }
}

/// Main view model coordinating the entire migration workflow.
@MainActor
@Observable
final class MigrationViewModel {
    // MARK: - Navigation

    var currentStep: MigrationStep = .welcome
    var completedSteps: Set<MigrationStep> = []

    // MARK: - Account Configuration

    var sourceAccount = EmailAccount()
    var destinationAccount = EmailAccount() {
        didSet {
            // Default destination port based on protocol
            if destinationAccount.port == sourceAccount.port
                || destinationAccount.port == 993 && destinationAccount.mailProtocol != .imap {
                destinationAccount.port = destinationAccount.mailProtocol.defaultPort
            }
        }
    }

    // MARK: - Connection State

    var isConnectingSource = false
    var isConnectingDestination = false
    var sourceConnectionStatus: ConnectionStatus = .disconnected
    var destinationConnectionStatus: ConnectionStatus = .disconnected
    var connectionError: String?

    // MARK: - Folder Data

    var sourceFolders: [EmailFolder] = []
    var destinationFolders: [EmailFolder] = []
    var folderMappings: [FolderMapping] = []

    // MARK: - Migration

    var engine: MigrationEngine?
    var hasResumableState = false
    var resumableState: MigrationState?

    // MARK: - Settings

    var maxConcurrency: Int = 3
    var batchSize: Int = 20
    var throttleDelay: Int = 0 // ms
    var autoResumeOnLaunch: Bool = true

    // MARK: - Dependencies

    private let store = MigrationStore()
    private var sourceService: (any EmailService)?
    private var destinationService: (any EmailService)?

    // MARK: - Initialization

    init() {
        Task { await checkForResumableState() }
    }

    // MARK: - Navigation

    var canGoNext: Bool {
        switch currentStep {
        case .welcome: return true
        case .sourceAccount: return sourceConnectionStatus == .connected
        case .destinationAccount: return destinationConnectionStatus == .connected
        case .folderMapping: return !folderMappings.filter(\.isEnabled).isEmpty
        case .migration: return engine?.state.status == .completed
        case .completion: return false
        }
    }

    var canGoBack: Bool {
        currentStep != .welcome && currentStep != .migration
    }

    func goNext() {
        completedSteps.insert(currentStep)
        if let nextIndex = MigrationStep.allCases.firstIndex(of: currentStep),
           nextIndex + 1 < MigrationStep.allCases.count {
            currentStep = MigrationStep.allCases[nextIndex + 1]
        }
    }

    func goBack() {
        if let currentIndex = MigrationStep.allCases.firstIndex(of: currentStep),
           currentIndex > 0 {
            currentStep = MigrationStep.allCases[currentIndex - 1]
        }
    }

    func goToStep(_ step: MigrationStep) {
        if completedSteps.contains(step) || step.rawValue <= currentStep.rawValue {
            currentStep = step
        }
    }

    // MARK: - Connection

    func connectSource() async {
        isConnectingSource = true
        connectionError = nil
        sourceConnectionStatus = .connecting

        do {
            let service = createService(for: sourceAccount)
            try await service.connect(
                host: sourceAccount.hostname,
                port: sourceAccount.port,
                useTLS: sourceAccount.useTLS
            )

            let password = KeychainHelper.loadPassword(for: sourceAccount.keychainKey) ?? ""
            if sourceAccount.authMethod == .oauth2 {
                try await service.authenticateOAuth2(username: sourceAccount.username, accessToken: password)
            } else {
                try await service.authenticate(username: sourceAccount.username, password: password)
            }

            // Fetch folders
            let folders = try await service.listFolders()

            // Get message counts by selecting each folder
            var detailedFolders: [EmailFolder] = []
            for folder in folders {
                do {
                    let status = try await service.selectFolder(folder.path)
                    var updatedFolder = folder
                    updatedFolder = EmailFolder(
                        path: folder.path,
                        name: folder.name,
                        delimiter: folder.delimiter,
                        flags: folder.flags,
                        messageCount: status.messageCount
                    )
                    detailedFolders.append(updatedFolder)
                } catch {
                    detailedFolders.append(folder)
                }
            }

            sourceService = service
            sourceFolders = detailedFolders
            sourceConnectionStatus = .connected
        } catch {
            sourceConnectionStatus = .error
            connectionError = error.localizedDescription
            sourceService = nil
        }

        isConnectingSource = false
    }

    func connectDestination() async {
        isConnectingDestination = true
        connectionError = nil
        destinationConnectionStatus = .connecting

        do {
            let service = createService(for: destinationAccount)
            try await service.connect(
                host: destinationAccount.hostname,
                port: destinationAccount.port,
                useTLS: destinationAccount.useTLS
            )

            let password = KeychainHelper.loadPassword(for: destinationAccount.keychainKey) ?? ""
            if destinationAccount.authMethod == .oauth2 {
                try await service.authenticateOAuth2(username: destinationAccount.username, accessToken: password)
            } else {
                try await service.authenticate(username: destinationAccount.username, password: password)
            }

            let folders = try await service.listFolders()

            destinationService = service
            destinationFolders = folders
            destinationConnectionStatus = .connected

            // Auto-generate folder mappings
            folderMappings = FolderMapper.generateMappings(
                sourceFolders: sourceFolders,
                destinationFolders: destinationFolders
            )
        } catch {
            destinationConnectionStatus = .error
            connectionError = error.localizedDescription
            destinationService = nil
        }

        isConnectingDestination = false
    }

    func savePassword(_ password: String, for account: EmailAccount) {
        try? KeychainHelper.savePassword(password, for: account.keychainKey)
    }

    // MARK: - Migration Control

    func startMigration() {
        guard let source = sourceService, let dest = destinationService else { return }

        let migrationState: MigrationState
        if let resumable = resumableState {
            migrationState = resumable
        } else {
            migrationState = MigrationState(source: sourceAccount, destination: destinationAccount)
        }

        let newEngine = MigrationEngine(state: migrationState, store: store)
        newEngine.maxConcurrentMessages = maxConcurrency
        newEngine.batchSize = batchSize
        newEngine.throttleDelayMs = throttleDelay
        self.engine = newEngine

        newEngine.start(
            source: source,
            destination: dest,
            mappings: folderMappings
        )
    }

    func pauseMigration() {
        engine?.pause()
    }

    func resumeMigration() {
        engine?.resume()
    }

    func cancelMigration() {
        engine?.cancel()
    }

    // MARK: - Resume Support

    func checkForResumableState() async {
        if let state = try? await store.findResumable() {
            resumableState = state
            hasResumableState = true
        }
    }

    func resumeFromSavedState() {
        guard let state = resumableState else { return }
        sourceAccount = state.sourceAccount
        destinationAccount = state.destinationAccount
        currentStep = .migration
    }

    func discardResumableState() {
        if let state = resumableState {
            try? store.delete(id: state.id)
        }
        resumableState = nil
        hasResumableState = false
    }

    // MARK: - Helpers

    private func createService(for account: EmailAccount) -> any EmailService {
        switch account.mailProtocol {
        case .imap: return IMAPService()
        case .pop3: return POP3Service()
        case .exchange: return ExchangeService()
        }
    }
}

/// Connection status indicator.
enum ConnectionStatus {
    case disconnected
    case connecting
    case connected
    case error

    var color: Color {
        switch self {
        case .disconnected: return .secondary
        case .connecting: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }

    var label: String {
        switch self {
        case .disconnected: return "Not Connected"
        case .connecting: return "Connecting..."
        case .connected: return "Connected"
        case .error: return "Error"
        }
    }

    var icon: String {
        switch self {
        case .disconnected: return "circle"
        case .connecting: return "circle.dotted"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        }
    }
}
