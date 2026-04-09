import Foundation

/// The email protocol used to connect to a mail server.
enum MailProtocol: String, Codable, CaseIterable, Identifiable {
    case imap = "IMAP"
    case pop3 = "POP3"
    case exchange = "Exchange (EWS)"

    var id: String { rawValue }

    var defaultPort: UInt16 {
        switch self {
        case .imap: return 993
        case .pop3: return 995
        case .exchange: return 443
        }
    }

    var defaultUseTLS: Bool { true }
}

/// Authentication method for connecting to a mail server.
enum AuthMethod: String, Codable, CaseIterable, Identifiable {
    case password = "Password"
    case oauth2 = "OAuth 2.0"

    var id: String { rawValue }
}

/// Represents a configured email account for migration.
struct EmailAccount: Codable, Identifiable, Hashable {
    var id = UUID()
    var displayName: String = ""
    var emailAddress: String = ""
    var hostname: String = ""
    var port: UInt16 = 993
    var username: String = ""
    var useTLS: Bool = true
    var mailProtocol: MailProtocol = .imap
    var authMethod: AuthMethod = .password

    /// The Keychain key used to store this account's credentials.
    var keychainKey: String {
        "\(mailProtocol.rawValue)://\(username)@\(hostname):\(port)"
    }

    /// Whether this account has enough information to attempt a connection.
    var isConfigured: Bool {
        !hostname.isEmpty && !username.isEmpty
    }
}
