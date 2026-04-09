import Foundation

/// POP3 client implementation using Network framework.
/// POP3 only supports inbox access — no folder hierarchy.
final class POP3Service: EmailService, @unchecked Sendable {
    private var connection: TCPConnection?
    private var buffer = Data()
    private var messageCount = 0

    // MARK: - Connection

    func connect(host: String, port: UInt16, useTLS: Bool) async throws {
        let conn = TCPConnection(host: host, port: port, useTLS: useTLS)
        try await conn.start()
        self.connection = conn
        self.buffer = Data()

        // Read server greeting
        let greeting = try await readLine()
        guard greeting.hasPrefix("+OK") else {
            throw EmailServiceError.connectionFailed("POP3 greeting: \(greeting)")
        }
    }

    func disconnect() async throws {
        try? await sendCommand("QUIT")
        connection?.cancel()
        connection = nil
    }

    // MARK: - Authentication

    func authenticate(username: String, password: String) async throws {
        let userResponse = try await sendCommand("USER \(username)")
        guard userResponse.hasPrefix("+OK") else {
            throw EmailServiceError.authenticationFailed("USER rejected: \(userResponse)")
        }

        let passResponse = try await sendCommand("PASS \(password)")
        guard passResponse.hasPrefix("+OK") else {
            throw EmailServiceError.authenticationFailed("Authentication failed")
        }
    }

    func authenticateOAuth2(username: String, accessToken: String) async throws {
        // POP3 XOAUTH2 via AUTH command
        let authString = "user=\(username)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        guard let authData = authString.data(using: .utf8) else {
            throw EmailServiceError.authenticationFailed("Failed to encode OAuth2 token")
        }
        let encoded = authData.base64EncodedString()

        let response = try await sendCommand("AUTH XOAUTH2 \(encoded)")
        guard response.hasPrefix("+OK") else {
            throw EmailServiceError.authenticationFailed("OAuth2 failed: \(response)")
        }
    }

    // MARK: - Folder Operations (limited in POP3)

    func listFolders() async throws -> [EmailFolder] {
        // POP3 only has INBOX — update message count via STAT
        let stat = try await sendCommand("STAT")
        guard stat.hasPrefix("+OK") else {
            throw EmailServiceError.commandFailed("STAT failed: \(stat)")
        }

        let parts = stat.split(separator: " ")
        if parts.count >= 2, let count = Int(parts[1]) {
            messageCount = count
        }

        return [
            EmailFolder(
                path: "INBOX",
                name: "Inbox",
                delimiter: "/",
                flags: [],
                messageCount: messageCount
            )
        ]
    }

    func selectFolder(_ path: String) async throws -> FolderStatus {
        // POP3 only supports INBOX
        guard path.uppercased() == "INBOX" else {
            throw EmailServiceError.folderNotFound("POP3 only supports INBOX, not \(path)")
        }

        // Get message count
        let stat = try await sendCommand("STAT")
        guard stat.hasPrefix("+OK") else {
            throw EmailServiceError.commandFailed("STAT failed: \(stat)")
        }

        let parts = stat.split(separator: " ")
        let count = parts.count >= 2 ? Int(parts[1]) ?? 0 : 0
        messageCount = count

        return FolderStatus(messageCount: count, uidValidity: 0, uidNext: UInt32(count + 1))
    }

    func createFolder(_ path: String) async throws {
        throw EmailServiceError.protocolNotSupported("POP3 does not support folder creation")
    }

    // MARK: - Message Operations

    func fetchMessageUIDs() async throws -> [UInt32] {
        // POP3 uses message numbers, not UIDs. We'll use UIDL if available.
        let response = try await sendMultiLineCommand("UIDL")

        if response.hasPrefix("-ERR") {
            // UIDL not supported — use sequential numbers
            return (1...UInt32(messageCount)).map { $0 }
        }

        // Parse UIDL response: "number unique-id"
        var uids: [UInt32] = []
        let lines = response.split(separator: "\n")
        for line in lines {
            let parts = line.split(separator: " ")
            if let num = parts.first, let uid = UInt32(num) {
                uids.append(uid)
            }
        }
        return uids.isEmpty ? (1...UInt32(max(1, messageCount))).map { $0 } : uids
    }

    func fetchMessage(uid: UInt32) async throws -> MessageData {
        // In POP3, uid is the message number
        let response = try await sendMultiLineCommand("RETR \(uid)")

        guard !response.hasPrefix("-ERR") else {
            throw EmailServiceError.commandFailed("RETR failed: \(response)")
        }

        guard let data = response.data(using: .utf8) else {
            throw EmailServiceError.invalidResponse("Failed to decode message data")
        }

        return MessageData(
            uid: uid,
            flags: [],  // POP3 has no flag concept
            internalDate: nil,
            rawData: data,
            size: data.count
        )
    }

    func appendMessage(_ data: Data, toFolder folder: String,
                       flags: [String], internalDate: Date?) async throws {
        throw EmailServiceError.protocolNotSupported(
            "POP3 does not support message upload. Use POP3 only as a source."
        )
    }

    // MARK: - Protocol Internals

    private func sendCommand(_ command: String) async throws -> String {
        guard let connection else { throw EmailServiceError.notConnected }
        try await connection.sendString("\(command)\r\n")
        return try await readLine()
    }

    /// Send a command and read a multi-line response (terminated by ".\r\n").
    private func sendMultiLineCommand(_ command: String) async throws -> String {
        guard let connection else { throw EmailServiceError.notConnected }
        try await connection.sendString("\(command)\r\n")

        // First line is the status
        let status = try await readLine()
        guard status.hasPrefix("+OK") else { return status }

        // Read lines until a lone "."
        var lines: [String] = []
        while true {
            let line = try await readLine()
            if line == "." { break }
            // Byte-stuff removal: lines starting with ".." become "."
            if line.hasPrefix("..") {
                lines.append(String(line.dropFirst()))
            } else {
                lines.append(line)
            }
        }
        return lines.joined(separator: "\n")
    }

    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A])
        while true {
            if let range = buffer.range(of: crlf) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<range.upperBound)
                return String(data: lineData, encoding: .utf8) ?? ""
            }
            guard let connection else { throw EmailServiceError.notConnected }
            let chunk = try await connection.receive()
            buffer.append(chunk)
        }
    }
}
