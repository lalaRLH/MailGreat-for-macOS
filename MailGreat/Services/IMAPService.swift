import Foundation

/// Full IMAP client implementation using Network framework (NWConnection).
/// Supports LOGIN, XOAUTH2, LIST, SELECT, UID FETCH, APPEND, CREATE.
final class IMAPService: EmailService, @unchecked Sendable {
    private var connection: TCPConnection?
    private var buffer = Data()
    private var tagCounter = 0
    private let lock = NSLock()

    // MARK: - Connection

    func connect(host: String, port: UInt16, useTLS: Bool) async throws {
        let conn = TCPConnection(host: host, port: port, useTLS: useTLS)
        try await conn.start()
        self.connection = conn
        self.buffer = Data()
        self.tagCounter = 0

        // Read server greeting
        let greeting = try await readLine()
        guard greeting.hasPrefix("* OK") || greeting.hasPrefix("* PREAUTH") else {
            throw EmailServiceError.connectionFailed("Unexpected greeting: \(greeting)")
        }
    }

    func disconnect() async throws {
        let tag = nextTag()
        try? await sendRaw("\(tag) LOGOUT\r\n")
        _ = try? await readTaggedResponse(tag: tag)
        connection?.cancel()
        connection = nil
    }

    // MARK: - Authentication

    func authenticate(username: String, password: String) async throws {
        // Escape special characters in credentials
        let escapedUser = username.replacingOccurrences(of: "\"", with: "\\\"")
        let escapedPass = password.replacingOccurrences(of: "\"", with: "\\\"")

        let tag = nextTag()
        try await sendRaw("\(tag) LOGIN \"\(escapedUser)\" \"\(escapedPass)\"\r\n")
        let response = try await readTaggedResponse(tag: tag)

        guard response.status == .ok else {
            throw EmailServiceError.authenticationFailed(response.statusLine)
        }
    }

    func authenticateOAuth2(username: String, accessToken: String) async throws {
        // XOAUTH2 SASL mechanism: base64("user=" + user + "\x01auth=Bearer " + token + "\x01\x01")
        let authString = "user=\(username)\u{01}auth=Bearer \(accessToken)\u{01}\u{01}"
        guard let authData = authString.data(using: .utf8) else {
            throw EmailServiceError.authenticationFailed("Failed to encode OAuth2 token")
        }
        let encoded = authData.base64EncodedString()

        let tag = nextTag()
        try await sendRaw("\(tag) AUTHENTICATE XOAUTH2 \(encoded)\r\n")
        let response = try await readTaggedResponse(tag: tag)

        guard response.status == .ok else {
            throw EmailServiceError.authenticationFailed(response.statusLine)
        }
    }

    // MARK: - Folder Operations

    func listFolders() async throws -> [EmailFolder] {
        let tag = nextTag()
        try await sendRaw("\(tag) LIST \"\" \"*\"\r\n")
        let response = try await readTaggedResponse(tag: tag)

        guard response.status == .ok else {
            throw EmailServiceError.commandFailed(response.statusLine)
        }

        var folders: [EmailFolder] = []
        for line in response.untaggedLines {
            if let folder = parseListResponse(line) {
                // Skip non-selectable folders
                if !folder.flags.contains("\\Noselect") && !folder.flags.contains("\\NonExistent") {
                    folders.append(folder)
                }
            }
        }
        return folders.sorted { $0.path < $1.path }
    }

    func selectFolder(_ path: String) async throws -> FolderStatus {
        let tag = nextTag()
        try await sendRaw("\(tag) SELECT \"\(escapeFolderName(path))\"\r\n")
        let response = try await readTaggedResponse(tag: tag)

        guard response.status == .ok else {
            throw EmailServiceError.folderNotFound(path)
        }

        var messageCount = 0
        var uidValidity: UInt32 = 0
        var uidNext: UInt32 = 0

        for line in response.untaggedLines {
            if line.hasSuffix("EXISTS") {
                let parts = line.split(separator: " ")
                if parts.count >= 2, let count = Int(parts[1]) {
                    messageCount = count
                }
            } else if line.contains("UIDVALIDITY") {
                if let val = extractBracketedValue(from: line, key: "UIDVALIDITY") {
                    uidValidity = UInt32(val) ?? 0
                }
            } else if line.contains("UIDNEXT") {
                if let val = extractBracketedValue(from: line, key: "UIDNEXT") {
                    uidNext = UInt32(val) ?? 0
                }
            }
        }

        return FolderStatus(
            messageCount: messageCount,
            uidValidity: uidValidity,
            uidNext: uidNext
        )
    }

    func createFolder(_ path: String) async throws {
        let tag = nextTag()
        try await sendRaw("\(tag) CREATE \"\(escapeFolderName(path))\"\r\n")
        let response = try await readTaggedResponse(tag: tag)

        // ALREADYEXISTS is acceptable
        if response.status == .no && response.statusLine.contains("ALREADYEXISTS") {
            return
        }
        guard response.status == .ok || response.status == .no else {
            throw EmailServiceError.commandFailed("CREATE failed: \(response.statusLine)")
        }
    }

    // MARK: - Message Operations

    func fetchMessageUIDs() async throws -> [UInt32] {
        let tag = nextTag()
        try await sendRaw("\(tag) UID SEARCH ALL\r\n")
        let response = try await readTaggedResponse(tag: tag)

        guard response.status == .ok else {
            throw EmailServiceError.commandFailed(response.statusLine)
        }

        var uids: [UInt32] = []
        for line in response.untaggedLines {
            if line.hasPrefix("* SEARCH") {
                let parts = line.dropFirst("* SEARCH".count).split(separator: " ")
                for part in parts {
                    if let uid = UInt32(part) {
                        uids.append(uid)
                    }
                }
            }
        }
        return uids.sorted()
    }

    func fetchMessage(uid: UInt32) async throws -> MessageData {
        let tag = nextTag()
        try await sendRaw("\(tag) UID FETCH \(uid) (FLAGS INTERNALDATE RFC822)\r\n")

        var flags: [String] = []
        var internalDate: Date?
        var messageBody = Data()

        // Read lines until we get the tagged response
        while true {
            let line = try await readLine()

            // Tagged response — we're done
            if line.hasPrefix(tag) {
                if line.contains("OK") {
                    break
                } else {
                    throw EmailServiceError.commandFailed("FETCH failed: \(line)")
                }
            }

            // Untagged FETCH response
            if line.hasPrefix("*") && line.contains("FETCH") {
                // Parse flags
                flags = parseFetchFlags(from: line)

                // Parse internal date
                internalDate = parseFetchInternalDate(from: line)

                // Check for RFC822 literal
                if let literalSize = extractLiteralSize(from: line) {
                    messageBody = try await readExactBytes(literalSize)
                    // Read trailing line after literal (usually ")")
                    _ = try await readLine()
                }
            }
        }

        return MessageData(
            uid: uid,
            flags: flags,
            internalDate: internalDate,
            rawData: messageBody,
            size: messageBody.count
        )
    }

    func appendMessage(_ data: Data, toFolder folder: String,
                       flags: [String], internalDate: Date?) async throws {
        let flagsStr = flags.isEmpty ? "" : " (\(flags.joined(separator: " ")))"
        let dateStr = internalDate.map { " \"\(formatIMAPDate($0))\"" } ?? ""
        let tag = nextTag()

        try await sendRaw("\(tag) APPEND \"\(escapeFolderName(folder))\"\(flagsStr)\(dateStr) {\(data.count)}\r\n")

        // Wait for continuation request (+)
        let cont = try await readLine()
        guard cont.hasPrefix("+") else {
            throw EmailServiceError.commandFailed("APPEND rejected: \(cont)")
        }

        // Send the message data followed by CRLF
        try await connection!.send(data)
        try await sendRaw("\r\n")

        // Read tagged response
        let response = try await readTaggedResponse(tag: tag)
        guard response.status == .ok else {
            throw EmailServiceError.commandFailed("APPEND failed: \(response.statusLine)")
        }
    }

    // MARK: - Protocol Internals

    private func nextTag() -> String {
        lock.lock()
        tagCounter += 1
        let tag = "A\(String(format: "%04d", tagCounter))"
        lock.unlock()
        return tag
    }

    private func sendRaw(_ string: String) async throws {
        guard let connection else { throw EmailServiceError.notConnected }
        try await connection.sendString(string)
    }

    /// Read a single line from the connection (up to \r\n).
    private func readLine() async throws -> String {
        let crlf = Data([0x0D, 0x0A]) // \r\n
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

    /// Read exactly `count` bytes from the buffer/connection.
    private func readExactBytes(_ count: Int) async throws -> Data {
        while buffer.count < count {
            guard let connection else { throw EmailServiceError.notConnected }
            let chunk = try await connection.receive()
            buffer.append(chunk)
        }
        let data = buffer.prefix(count)
        buffer.removeSubrange(buffer.startIndex..<buffer.startIndex.advanced(by: count))
        return Data(data)
    }

    /// Read until a tagged response is found, collecting untagged lines.
    private func readTaggedResponse(tag: String) async throws -> IMAPTaggedResponse {
        var untaggedLines: [String] = []
        while true {
            let line = try await readLine()
            if line.hasPrefix(tag) {
                let status: IMAPResponseStatus
                if line.contains(" OK ") || line.hasSuffix(" OK") {
                    status = .ok
                } else if line.contains(" NO ") || line.hasSuffix(" NO") {
                    status = .no
                } else {
                    status = .bad
                }
                return IMAPTaggedResponse(
                    tag: tag,
                    status: status,
                    statusLine: line,
                    untaggedLines: untaggedLines
                )
            } else {
                untaggedLines.append(line)
            }
        }
    }

    // MARK: - Parsing Helpers

    private func parseListResponse(_ line: String) -> EmailFolder? {
        // Format: * LIST (\flags) "delimiter" "folder name"
        guard line.hasPrefix("* LIST") || line.hasPrefix("* LSUB") else { return nil }

        // Extract flags between first ( and )
        guard let flagStart = line.firstIndex(of: "("),
              let flagEnd = line.firstIndex(of: ")") else { return nil }

        let flagsStr = String(line[line.index(after: flagStart)..<flagEnd])
        let flags = Set(flagsStr.split(separator: " ").map(String.init))

        // After the flags, expect "delimiter" "name"
        let afterFlags = String(line[line.index(after: flagEnd)...]).trimmingCharacters(in: .whitespaces)

        // Parse delimiter
        var delimiter = "/"
        var remainder = afterFlags
        if let delimStart = afterFlags.firstIndex(of: "\"") {
            let afterDelimStart = afterFlags.index(after: delimStart)
            if let delimEnd = afterFlags[afterDelimStart...].firstIndex(of: "\"") {
                delimiter = String(afterFlags[afterDelimStart..<delimEnd])
                remainder = String(afterFlags[afterFlags.index(after: delimEnd)...])
                    .trimmingCharacters(in: .whitespaces)
            }
        } else if afterFlags.hasPrefix("NIL") {
            delimiter = ""
            remainder = String(afterFlags.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        }

        // Parse folder name (may be quoted or unquoted)
        let folderName: String
        if remainder.hasPrefix("\"") {
            let inner = remainder.dropFirst()
            if let end = inner.firstIndex(of: "\"") {
                folderName = String(inner[inner.startIndex..<end])
            } else {
                folderName = String(inner)
            }
        } else {
            folderName = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let displayName = folderName.split(separator: Character(delimiter)).last.map(String.init) ?? folderName

        return EmailFolder(
            path: folderName,
            name: displayName,
            delimiter: delimiter,
            flags: flags,
            messageCount: 0
        )
    }

    private func parseFetchFlags(from line: String) -> [String] {
        guard let flagStart = line.range(of: "FLAGS (")?.upperBound,
              let flagEnd = line[flagStart...].firstIndex(of: ")") else {
            return []
        }
        return line[flagStart..<flagEnd]
            .split(separator: " ")
            .map(String.init)
    }

    private func parseFetchInternalDate(from line: String) -> Date? {
        guard let dateStart = line.range(of: "INTERNALDATE \"")?.upperBound,
              let dateEnd = line[dateStart...].firstIndex(of: "\"") else {
            return nil
        }
        let dateStr = String(line[dateStart..<dateEnd])
        return parseIMAPDate(dateStr)
    }

    private func extractLiteralSize(from line: String) -> Int? {
        guard let braceStart = line.lastIndex(of: "{"),
              let braceEnd = line.lastIndex(of: "}"),
              braceStart < braceEnd else { return nil }
        let sizeStr = line[line.index(after: braceStart)..<braceEnd]
        return Int(sizeStr)
    }

    private func extractBracketedValue(from line: String, key: String) -> String? {
        guard let range = line.range(of: "\(key) ") else { return nil }
        let afterKey = line[range.upperBound...]
        let value = afterKey.prefix(while: { $0.isNumber })
        return value.isEmpty ? nil : String(value)
    }

    private func escapeFolderName(_ name: String) -> String {
        name.replacingOccurrences(of: "\"", with: "\\\"")
    }

    // MARK: - Date Formatting

    private func formatIMAPDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "dd-MMM-yyyy HH:mm:ss Z"
        return formatter.string(from: date)
    }

    private func parseIMAPDate(_ string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // Try common IMAP date formats
        for format in [
            "dd-MMM-yyyy HH:mm:ss Z",
            "d-MMM-yyyy HH:mm:ss Z",
            " d-MMM-yyyy HH:mm:ss Z"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

// MARK: - Response Types

private struct IMAPTaggedResponse {
    let tag: String
    let status: IMAPResponseStatus
    let statusLine: String
    let untaggedLines: [String]
}

private enum IMAPResponseStatus {
    case ok, no, bad
}
