import Foundation

/// Data for a single email message retrieved from a server.
struct MessageData {
    let uid: UInt32
    let flags: [String]
    let internalDate: Date?
    let rawData: Data
    let size: Int
}

/// Status after selecting a folder.
struct FolderStatus {
    let messageCount: Int
    let uidValidity: UInt32
    let uidNext: UInt32
}

/// Errors originating from email service operations.
enum EmailServiceError: LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case commandFailed(String)
    case invalidResponse(String)
    case connectionClosed
    case timeout
    case folderNotFound(String)
    case notConnected
    case protocolNotSupported(String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .invalidResponse(let msg): return "Invalid response: \(msg)"
        case .connectionClosed: return "Connection closed unexpectedly"
        case .timeout: return "Operation timed out"
        case .folderNotFound(let name): return "Folder not found: \(name)"
        case .notConnected: return "Not connected to server"
        case .protocolNotSupported(let msg): return "Protocol not supported: \(msg)"
        }
    }
}

/// Protocol for all email service implementations (IMAP, POP3, Exchange).
protocol EmailService: AnyObject, Sendable {

    /// Connect to the mail server.
    func connect(host: String, port: UInt16, useTLS: Bool) async throws

    /// Authenticate with username/password.
    func authenticate(username: String, password: String) async throws

    /// Authenticate with OAuth2 access token.
    func authenticateOAuth2(username: String, accessToken: String) async throws

    /// List all available mail folders.
    func listFolders() async throws -> [EmailFolder]

    /// Select a folder and return its status.
    func selectFolder(_ path: String) async throws -> FolderStatus

    /// Fetch all message UIDs in the currently selected folder.
    func fetchMessageUIDs() async throws -> [UInt32]

    /// Fetch a complete message by UID including flags and raw RFC822 data.
    func fetchMessage(uid: UInt32) async throws -> MessageData

    /// Append a message to a folder on the destination server.
    func appendMessage(_ data: Data, toFolder folder: String,
                       flags: [String], internalDate: Date?) async throws

    /// Create a folder on the server.
    func createFolder(_ path: String) async throws

    /// Gracefully disconnect.
    func disconnect() async throws
}

/// Default no-op for optional methods.
extension EmailService {
    func authenticateOAuth2(username: String, accessToken: String) async throws {
        throw EmailServiceError.protocolNotSupported("OAuth2 not supported for this service")
    }
}
