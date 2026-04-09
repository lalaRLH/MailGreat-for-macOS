import Foundation

/// Persistent state for a migration job, enabling pause/resume.
struct MigrationState: Codable {
    var id: UUID
    var sourceAccount: EmailAccount
    var destinationAccount: EmailAccount
    var startedAt: Date
    var lastUpdatedAt: Date
    var status: MigrationStatus
    var folderStates: [FolderMigrationState]
    var statistics: MigrationStatistics

    init(source: EmailAccount, destination: EmailAccount) {
        self.id = UUID()
        self.sourceAccount = source
        self.destinationAccount = destination
        self.startedAt = Date()
        self.lastUpdatedAt = Date()
        self.status = .notStarted
        self.folderStates = []
        self.statistics = MigrationStatistics()
    }

    mutating func markMigrated(uid: UInt32, inFolder folderPath: String) {
        guard let index = folderStates.firstIndex(where: { $0.sourcePath == folderPath }) else {
            return
        }
        folderStates[index].migratedUIDs.insert(uid)
        statistics.migratedMessages += 1
        lastUpdatedAt = Date()
    }

    mutating func markFailed(uid: UInt32, inFolder folderPath: String, error: String) {
        guard let index = folderStates.firstIndex(where: { $0.sourcePath == folderPath }) else {
            return
        }
        folderStates[index].failedUIDs[uid] = error
        statistics.failedMessages += 1
        lastUpdatedAt = Date()
    }

    func isMigrated(uid: UInt32, inFolder folderPath: String) -> Bool {
        guard let state = folderStates.first(where: { $0.sourcePath == folderPath }) else {
            return false
        }
        return state.migratedUIDs.contains(uid)
    }
}

/// Status of the overall migration.
enum MigrationStatus: String, Codable {
    case notStarted
    case inProgress
    case paused
    case completed
    case failed
    case cancelled
}

/// Per-folder migration tracking.
struct FolderMigrationState: Codable, Identifiable {
    var id: String { sourcePath }
    let sourcePath: String
    let destinationPath: String
    var totalMessages: Int
    var migratedUIDs: Set<UInt32>
    var failedUIDs: [UInt32: String]
    var folderCreated: Bool
    var status: MigrationStatus

    var migratedCount: Int { migratedUIDs.count }
    var failedCount: Int { failedUIDs.count }
    var remainingCount: Int { max(0, totalMessages - migratedCount - failedCount) }
    var progress: Double {
        totalMessages > 0 ? Double(migratedCount) / Double(totalMessages) : 0
    }
}

/// Aggregate statistics for a migration.
struct MigrationStatistics: Codable {
    var totalFolders: Int = 0
    var completedFolders: Int = 0
    var totalMessages: Int = 0
    var migratedMessages: Int = 0
    var failedMessages: Int = 0
    var bytesTransferred: Int64 = 0
    var messagesPerSecond: Double = 0

    var overallProgress: Double {
        totalMessages > 0 ? Double(migratedMessages) / Double(totalMessages) : 0
    }
}
