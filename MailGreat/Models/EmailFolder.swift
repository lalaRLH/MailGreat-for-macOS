import Foundation

/// Represents a mail folder on a server.
struct EmailFolder: Codable, Identifiable, Hashable {
    var id: String { path }
    let path: String
    let name: String
    let delimiter: String
    let flags: Set<String>
    var messageCount: Int

    /// Well-known folder type derived from name/flags.
    var folderType: WellKnownFolder {
        WellKnownFolder.detect(path: path, flags: flags)
    }
}

/// Well-known standard mail folders.
enum WellKnownFolder: String, Codable, CaseIterable {
    case inbox
    case sent
    case drafts
    case trash
    case junk
    case archive
    case custom

    static func detect(path: String, flags: Set<String>) -> WellKnownFolder {
        let upper = path.uppercased()
        let lastComponent = path.split(separator: "/").last.map(String.init)?.uppercased()
            ?? upper

        // Check IMAP special-use flags first (RFC 6154)
        if flags.contains("\\Inbox") || upper == "INBOX" { return .inbox }
        if flags.contains("\\Sent") { return .sent }
        if flags.contains("\\Drafts") { return .drafts }
        if flags.contains("\\Trash") { return .trash }
        if flags.contains("\\Junk") { return .junk }
        if flags.contains("\\Archive") { return .archive }

        // Fallback to name matching
        switch lastComponent {
        case "INBOX": return .inbox
        case "SENT", "SENT ITEMS", "SENT MESSAGES", "SENT MAIL": return .sent
        case "DRAFTS", "DRAFT": return .drafts
        case "TRASH", "DELETED ITEMS", "DELETED MESSAGES", "BIN": return .trash
        case "JUNK", "SPAM", "JUNK E-MAIL", "BULK MAIL": return .junk
        case "ARCHIVE", "ALL MAIL", "ALL": return .archive
        default: return .custom
        }
    }
}
