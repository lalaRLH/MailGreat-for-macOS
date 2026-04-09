import Foundation

/// Core migration engine that orchestrates copying emails between servers.
/// Supports pause/resume, crash recovery, throttling, and progress reporting.
@MainActor
final class MigrationEngine: ObservableObject {
    // MARK: - Published State

    @Published var state: MigrationState
    @Published var isRunning = false
    @Published var isPaused = false
    @Published var currentFolder: String = ""
    @Published var currentMessage: Int = 0
    @Published var speed: Double = 0 // messages per second
    @Published var errors: [MigrationError] = []

    // MARK: - Dependencies

    private let store: MigrationStore
    private var sourceService: (any EmailService)?
    private var destinationService: (any EmailService)?
    private var migrationTask: Task<Void, Never>?
    private var speedTracker = SpeedTracker()

    // MARK: - Configuration

    var maxConcurrentMessages: Int = 3
    var batchSize: Int = 20
    var throttleDelayMs: Int = 0
    var cpuPriority: TaskPriority = .utility

    init(state: MigrationState, store: MigrationStore) {
        self.state = state
        self.store = store
    }

    // MARK: - Lifecycle

    func start(
        source: any EmailService,
        destination: any EmailService,
        mappings: [FolderMapping]
    ) {
        guard !isRunning else { return }

        self.sourceService = source
        self.destinationService = destination
        self.isRunning = true
        self.isPaused = false
        self.state.status = .inProgress
        self.errors = []

        // Initialize folder states for new migration
        if state.folderStates.isEmpty {
            state.folderStates = mappings.filter(\.isEnabled).map { mapping in
                FolderMigrationState(
                    sourcePath: mapping.sourceFolder.path,
                    destinationPath: mapping.destinationPath,
                    totalMessages: mapping.sourceFolder.messageCount,
                    migratedUIDs: [],
                    failedUIDs: [:],
                    folderCreated: false,
                    status: .notStarted
                )
            }
            state.statistics.totalFolders = state.folderStates.count
            state.statistics.totalMessages = state.folderStates.reduce(0) { $0 + $1.totalMessages }
        }

        migrationTask = Task(priority: cpuPriority) { [weak self] in
            await self?.runMigration()
        }
    }

    func pause() {
        isPaused = true
        state.status = .paused
        Task { try? await store.save(state) }
    }

    func resume() {
        guard isPaused else { return }
        isPaused = false
        state.status = .inProgress
    }

    func cancel() {
        migrationTask?.cancel()
        migrationTask = nil
        isRunning = false
        isPaused = false
        state.status = .cancelled
        Task { try? await store.save(state) }
    }

    // MARK: - Migration Loop

    private func runMigration() async {
        defer {
            Task { @MainActor in
                self.isRunning = false
                if self.state.status == .inProgress {
                    self.state.status = .completed
                }
                try? await self.store.save(self.state)
            }
        }

        for index in state.folderStates.indices {
            guard !Task.isCancelled else { return }

            let folderState = state.folderStates[index]
            if folderState.status == .completed { continue }

            await MainActor.run {
                currentFolder = folderState.sourcePath
                state.folderStates[index].status = .inProgress
            }

            do {
                try await migrateFolder(index: index)
                await MainActor.run {
                    state.folderStates[index].status = .completed
                    state.statistics.completedFolders += 1
                }
            } catch {
                let migrationError = MigrationError(
                    folder: folderState.sourcePath,
                    message: error.localizedDescription
                )
                await MainActor.run {
                    state.folderStates[index].status = .failed
                    errors.append(migrationError)
                }
            }

            // Save progress after each folder
            try? await store.save(state)
        }
    }

    private func migrateFolder(index: Int) async throws {
        guard let source = sourceService, let dest = destinationService else {
            throw EmailServiceError.notConnected
        }

        let folderState = state.folderStates[index]

        // Create destination folder if needed
        if !folderState.folderCreated {
            do {
                try await dest.createFolder(folderState.destinationPath)
            } catch {
                // Folder may already exist — that's fine
            }
            await MainActor.run {
                state.folderStates[index].folderCreated = true
            }
        }

        // Select source folder
        let status = try await source.selectFolder(folderState.sourcePath)
        await MainActor.run {
            state.folderStates[index].totalMessages = status.messageCount
        }

        // Get all UIDs
        let allUIDs = try await source.fetchMessageUIDs()
        let remaining = allUIDs.filter { !state.isMigrated(uid: $0, inFolder: folderState.sourcePath) }

        // Process in batches
        let batches = remaining.chunked(size: batchSize)

        for batch in batches {
            guard !Task.isCancelled else { return }

            // Wait while paused
            while isPaused {
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
            }

            for uid in batch {
                guard !Task.isCancelled else { return }

                while isPaused {
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled else { return }
                }

                do {
                    let message = try await source.fetchMessage(uid: uid)

                    try await dest.appendMessage(
                        message.rawData,
                        toFolder: folderState.destinationPath,
                        flags: message.flags,
                        internalDate: message.internalDate
                    )

                    await MainActor.run {
                        state.markMigrated(uid: uid, inFolder: folderState.sourcePath)
                        state.statistics.bytesTransferred += Int64(message.size)
                        currentMessage += 1
                        speedTracker.recordMessage()
                        speed = speedTracker.messagesPerSecond
                        state.statistics.messagesPerSecond = speed
                    }
                } catch {
                    await MainActor.run {
                        state.markFailed(
                            uid: uid,
                            inFolder: folderState.sourcePath,
                            error: error.localizedDescription
                        )
                    }
                }

                // Throttle between messages
                if throttleDelayMs > 0 {
                    try? await Task.sleep(for: .milliseconds(throttleDelayMs))
                }
            }

            // Save checkpoint after each batch
            try? await store.save(state)

            // Yield to prevent UI freezes
            await Task.yield()
        }
    }
}

// MARK: - Supporting Types

struct MigrationError: Identifiable {
    let id = UUID()
    let folder: String
    let message: String
    let timestamp = Date()
}

/// Tracks migration speed using a sliding window.
private struct SpeedTracker {
    private var timestamps: [Date] = []
    private let windowSeconds: TimeInterval = 30

    var messagesPerSecond: Double {
        let cutoff = Date().addingTimeInterval(-windowSeconds)
        let recent = timestamps.filter { $0 > cutoff }
        guard recent.count > 1, let first = recent.first else { return 0 }
        let elapsed = Date().timeIntervalSince(first)
        return elapsed > 0 ? Double(recent.count) / elapsed : 0
    }

    mutating func recordMessage() {
        let now = Date()
        timestamps.append(now)
        // Prune old entries
        let cutoff = now.addingTimeInterval(-windowSeconds * 2)
        timestamps.removeAll { $0 < cutoff }
    }
}

// MARK: - Array Extension

extension Array {
    func chunked(size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
