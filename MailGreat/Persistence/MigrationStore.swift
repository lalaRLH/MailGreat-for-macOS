import Foundation
import Security

/// Handles persistence of migration state to disk and credentials to Keychain.
/// State is stored as JSON in the app's Application Support directory.
final class MigrationStore {
    private let fileManager = FileManager.default

    /// Directory for storing migration state files.
    private var stateDirectory: URL {
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MailGreat", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// File URL for a specific migration state.
    private func stateFileURL(for id: UUID) -> URL {
        stateDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    // MARK: - State Persistence

    /// Save migration state to disk.
    func save(_ state: MigrationState) async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        let url = stateFileURL(for: state.id)
        try data.write(to: url, options: .atomic)
    }

    /// Load a specific migration state.
    func load(id: UUID) async throws -> MigrationState? {
        let url = stateFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(MigrationState.self, from: data)
    }

    /// List all saved migration states.
    func listAll() async throws -> [MigrationState] {
        let contents = try fileManager.contentsOfDirectory(
            at: stateDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var states: [MigrationState] = []
        for url in contents where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let state = try? decoder.decode(MigrationState.self, from: data) {
                states.append(state)
            }
        }

        return states.sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    /// Delete a migration state file.
    func delete(id: UUID) throws {
        let url = stateFileURL(for: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    /// Find the most recent resumable migration.
    func findResumable() async throws -> MigrationState? {
        let all = try await listAll()
        return all.first { $0.status == .inProgress || $0.status == .paused }
    }
}

// MARK: - Keychain Helper

struct KeychainHelper {
    private static let service = "com.mailgreat.accounts"

    /// Save a password to the Keychain.
    static func savePassword(_ password: String, for account: String) throws {
        guard let data = password.data(using: .utf8) else { return }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Delete existing entry first
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    /// Retrieve a password from the Keychain.
    static func loadPassword(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a password from the Keychain.
    static func deletePassword(for account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
