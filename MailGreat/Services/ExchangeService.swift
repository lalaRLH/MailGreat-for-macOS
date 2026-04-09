import Foundation

/// Exchange Web Services (EWS) client using SOAP/XML over HTTPS.
/// Supports on-premises Exchange and Exchange Online (Office 365).
final class ExchangeService: EmailService, @unchecked Sendable {
    private var session: URLSession?
    private var ewsURL: URL?
    private var authHeader: String?
    private var selectedFolderId: String?

    // Well-known EWS folder IDs
    private static let wellKnownFolders: [String: String] = [
        "inbox": "inbox",
        "sentitems": "sentitems",
        "drafts": "drafts",
        "deleteditems": "deleteditems",
        "junkemail": "junkemail",
        "outbox": "outbox",
        "msgfolderroot": "msgfolderroot"
    ]

    // MARK: - Connection

    func connect(host: String, port: UInt16, useTLS: Bool) async throws {
        let scheme = useTLS ? "https" : "http"
        guard let url = URL(string: "\(scheme)://\(host):\(port)/EWS/Exchange.asmx") else {
            throw EmailServiceError.connectionFailed("Invalid EWS URL")
        }
        self.ewsURL = url

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
    }

    func disconnect() async throws {
        session?.invalidateAndCancel()
        session = nil
        ewsURL = nil
        authHeader = nil
    }

    // MARK: - Authentication

    func authenticate(username: String, password: String) async throws {
        // Basic authentication
        let credentials = "\(username):\(password)"
        guard let credData = credentials.data(using: .utf8) else {
            throw EmailServiceError.authenticationFailed("Failed to encode credentials")
        }
        authHeader = "Basic \(credData.base64EncodedString())"

        // Validate by fetching inbox
        let xml = ewsEnvelope("""
            <m:GetFolder>
                <m:FolderShape>
                    <t:BaseShape>IdOnly</t:BaseShape>
                </m:FolderShape>
                <m:FolderIds>
                    <t:DistinguishedFolderId Id="inbox"/>
                </m:FolderIds>
            </m:GetFolder>
        """)

        let response = try await performRequest(xml)
        guard response.contains("NoError") || response.contains("GetFolderResponseMessage") else {
            throw EmailServiceError.authenticationFailed("EWS authentication failed")
        }
    }

    func authenticateOAuth2(username: String, accessToken: String) async throws {
        authHeader = "Bearer \(accessToken)"

        // Validate
        let xml = ewsEnvelope("""
            <m:GetFolder>
                <m:FolderShape>
                    <t:BaseShape>IdOnly</t:BaseShape>
                </m:FolderShape>
                <m:FolderIds>
                    <t:DistinguishedFolderId Id="inbox"/>
                </m:FolderIds>
            </m:GetFolder>
        """)

        let response = try await performRequest(xml)
        guard response.contains("NoError") || response.contains("GetFolderResponseMessage") else {
            throw EmailServiceError.authenticationFailed("EWS OAuth2 authentication failed")
        }
    }

    // MARK: - Folder Operations

    func listFolders() async throws -> [EmailFolder] {
        let xml = ewsEnvelope("""
            <m:FindFolder Traversal="Deep">
                <m:FolderShape>
                    <t:BaseShape>Default</t:BaseShape>
                    <t:AdditionalProperties>
                        <t:FieldURI FieldURI="folder:FolderClass"/>
                        <t:FieldURI FieldURI="folder:TotalCount"/>
                        <t:FieldURI FieldURI="folder:DisplayName"/>
                    </t:AdditionalProperties>
                </m:FolderShape>
                <m:ParentFolderIds>
                    <t:DistinguishedFolderId Id="msgfolderroot"/>
                </m:ParentFolderIds>
            </m:FindFolder>
        """)

        let response = try await performRequest(xml)
        return parseEWSFolders(from: response)
    }

    func selectFolder(_ path: String) async throws -> FolderStatus {
        // For EWS, we resolve folder path to folder ID
        let folders = try await listFolders()
        guard let folder = folders.first(where: { $0.path == path || $0.name == path }) else {
            throw EmailServiceError.folderNotFound(path)
        }
        selectedFolderId = folder.path
        return FolderStatus(
            messageCount: folder.messageCount,
            uidValidity: 0,
            uidNext: 0
        )
    }

    func createFolder(_ path: String) async throws {
        let components = path.split(separator: "/")
        let folderName = components.last.map(String.init) ?? path
        let parentId = components.count > 1
            ? String(components.dropLast().joined(separator: "/"))
            : "msgfolderroot"

        let parentRef: String
        if Self.wellKnownFolders.keys.contains(parentId.lowercased()) {
            parentRef = "<t:DistinguishedFolderId Id=\"\(parentId.lowercased())\"/>"
        } else {
            parentRef = "<t:FolderId Id=\"\(escapeXML(parentId))\"/>"
        }

        let xml = ewsEnvelope("""
            <m:CreateFolder>
                <m:ParentFolderId>
                    \(parentRef)
                </m:ParentFolderId>
                <m:Folders>
                    <t:Folder>
                        <t:DisplayName>\(escapeXML(folderName))</t:DisplayName>
                    </t:Folder>
                </m:Folders>
            </m:CreateFolder>
        """)

        let response = try await performRequest(xml)
        // ErrorFolderExists is acceptable
        if !response.contains("NoError") && !response.contains("ErrorFolderExists") {
            throw EmailServiceError.commandFailed("CreateFolder failed for: \(path)")
        }
    }

    // MARK: - Message Operations

    func fetchMessageUIDs() async throws -> [UInt32] {
        guard let folderId = selectedFolderId else {
            throw EmailServiceError.notConnected
        }

        var allItems: [(String, Int)] = []
        var offset = 0
        let pageSize = 500

        while true {
            let folderRef: String
            if Self.wellKnownFolders.keys.contains(folderId.lowercased()) {
                folderRef = "<t:DistinguishedFolderId Id=\"\(folderId.lowercased())\"/>"
            } else {
                folderRef = "<t:FolderId Id=\"\(escapeXML(folderId))\"/>"
            }

            let xml = ewsEnvelope("""
                <m:FindItem Traversal="Shallow">
                    <m:ItemShape>
                        <t:BaseShape>IdOnly</t:BaseShape>
                    </m:ItemShape>
                    <m:IndexedPageItemView MaxEntriesReturned="\(pageSize)" Offset="\(offset)" BasePoint="Beginning"/>
                    <m:ParentFolderIds>
                        \(folderRef)
                    </m:ParentFolderIds>
                </m:FindItem>
            """)

            let response = try await performRequest(xml)
            let itemIds = parseEWSItemIds(from: response)

            if itemIds.isEmpty { break }
            allItems.append(contentsOf: itemIds.enumerated().map { ($1, offset + $0) })
            offset += itemIds.count

            if response.contains("IncludesLastItemInRange=\"true\"") { break }
        }

        // EWS uses string IDs, map to sequential UInt32 for protocol conformance
        // Store the mapping for later retrieval
        ewsItemIdMap = Dictionary(uniqueKeysWithValues: allItems.enumerated().map {
            (UInt32($0.offset + 1), $0.element.0)
        })

        return Array(ewsItemIdMap.keys).sorted()
    }

    // Internal mapping from UInt32 pseudo-UIDs to EWS ItemIds
    private var ewsItemIdMap: [UInt32: String] = [:]

    func fetchMessage(uid: UInt32) async throws -> MessageData {
        guard let itemId = ewsItemIdMap[uid] else {
            throw EmailServiceError.commandFailed("Unknown message UID: \(uid)")
        }

        let xml = ewsEnvelope("""
            <m:GetItem>
                <m:ItemShape>
                    <t:BaseShape>IdOnly</t:BaseShape>
                    <t:IncludeMimeContent>true</t:IncludeMimeContent>
                    <t:AdditionalProperties>
                        <t:FieldURI FieldURI="item:DateTimeReceived"/>
                        <t:FieldURI FieldURI="message:IsRead"/>
                    </t:AdditionalProperties>
                </m:ItemShape>
                <m:ItemIds>
                    <t:ItemId Id="\(escapeXML(itemId))"/>
                </m:ItemIds>
            </m:GetItem>
        """)

        let response = try await performRequest(xml)

        // Extract MIME content (base64)
        guard let mimeData = extractXMLValue(from: response, tag: "t:MimeContent") else {
            throw EmailServiceError.invalidResponse("No MIME content in GetItem response")
        }

        guard let rawData = Data(base64Encoded: mimeData, options: .ignoreUnknownCharacters) else {
            throw EmailServiceError.invalidResponse("Failed to decode MIME base64")
        }

        // Determine flags
        var flags: [String] = []
        if let isRead = extractXMLValue(from: response, tag: "t:IsRead"), isRead == "true" {
            flags.append("\\Seen")
        }

        // Parse date
        var internalDate: Date?
        if let dateStr = extractXMLValue(from: response, tag: "t:DateTimeReceived") {
            let formatter = ISO8601DateFormatter()
            internalDate = formatter.date(from: dateStr)
        }

        return MessageData(
            uid: uid,
            flags: flags,
            internalDate: internalDate,
            rawData: rawData,
            size: rawData.count
        )
    }

    func appendMessage(_ data: Data, toFolder folder: String,
                       flags: [String], internalDate: Date?) async throws {
        let mimeBase64 = data.base64EncodedString(options: .lineLength76Characters)
        let isRead = flags.contains("\\Seen") ? "true" : "false"

        let folderRef: String
        if Self.wellKnownFolders.keys.contains(folder.lowercased()) {
            folderRef = "<t:DistinguishedFolderId Id=\"\(folder.lowercased())\"/>"
        } else {
            folderRef = "<t:FolderId Id=\"\(escapeXML(folder))\"/>"
        }

        let xml = ewsEnvelope("""
            <m:CreateItem MessageDisposition="SaveOnly">
                <m:SavedItemFolderId>
                    \(folderRef)
                </m:SavedItemFolderId>
                <m:Items>
                    <t:Message>
                        <t:MimeContent CharacterSet="UTF-8">\(mimeBase64)</t:MimeContent>
                        <t:IsRead>\(isRead)</t:IsRead>
                    </t:Message>
                </m:Items>
            </m:CreateItem>
        """)

        let response = try await performRequest(xml)
        guard response.contains("NoError") else {
            throw EmailServiceError.commandFailed("CreateItem failed for folder: \(folder)")
        }
    }

    // MARK: - HTTP / SOAP

    private func performRequest(_ body: String) async throws -> String {
        guard let url = ewsURL, let session else {
            throw EmailServiceError.notConnected
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("text/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        if let authHeader {
            request.setValue(authHeader, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body.data(using: .utf8)

        let (data, httpResponse) = try await session.data(for: request)

        if let http = httpResponse as? HTTPURLResponse, http.statusCode == 401 {
            throw EmailServiceError.authenticationFailed("HTTP 401 Unauthorized")
        }

        guard let responseString = String(data: data, encoding: .utf8) else {
            throw EmailServiceError.invalidResponse("Failed to decode EWS response")
        }

        return responseString
    }

    private func ewsEnvelope(_ body: String) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <soap:Envelope xmlns:soap="http://schemas.xmlsoap.org/soap/envelope/"
                       xmlns:t="http://schemas.microsoft.com/exchange/services/2006/types"
                       xmlns:m="http://schemas.microsoft.com/exchange/services/2006/messages">
            <soap:Header>
                <t:RequestServerVersion Version="Exchange2013_SP1"/>
            </soap:Header>
            <soap:Body>
                \(body)
            </soap:Body>
        </soap:Envelope>
        """
    }

    // MARK: - XML Parsing Helpers

    private func parseEWSFolders(from xml: String) -> [EmailFolder] {
        var folders: [EmailFolder] = []
        let folderPattern = "<t:Folder>"
        var searchRange = xml.startIndex

        while let start = xml.range(of: folderPattern, range: searchRange..<xml.endIndex) {
            guard let end = xml.range(of: "</t:Folder>", range: start.upperBound..<xml.endIndex) else {
                break
            }
            let chunk = String(xml[start.lowerBound..<end.upperBound])

            let displayName = extractXMLValue(from: chunk, tag: "t:DisplayName") ?? "Unknown"
            let folderId = extractXMLAttribute(from: chunk, tag: "t:FolderId", attribute: "Id") ?? ""
            let totalCount = Int(extractXMLValue(from: chunk, tag: "t:TotalCount") ?? "0") ?? 0

            if !folderId.isEmpty {
                folders.append(EmailFolder(
                    path: folderId,
                    name: displayName,
                    delimiter: "/",
                    flags: [],
                    messageCount: totalCount
                ))
            }

            searchRange = end.upperBound
        }
        return folders
    }

    private func parseEWSItemIds(from xml: String) -> [String] {
        var ids: [String] = []
        let pattern = "ItemId Id=\""
        var searchRange = xml.startIndex

        while let start = xml.range(of: pattern, range: searchRange..<xml.endIndex) {
            let afterQuote = start.upperBound
            if let end = xml[afterQuote...].firstIndex(of: "\"") {
                ids.append(String(xml[afterQuote..<end]))
                searchRange = end
            } else {
                break
            }
        }
        return ids
    }

    private func extractXMLValue(from xml: String, tag: String) -> String? {
        let openTag = "<\(tag)"
        guard let openStart = xml.range(of: openTag) else { return nil }

        // Find the end of the opening tag (handle attributes)
        guard let openEnd = xml[openStart.upperBound...].firstIndex(of: ">") else { return nil }
        let contentStart = xml.index(after: openEnd)

        let closeTag = "</\(tag)>"
        guard let closeRange = xml.range(of: closeTag, range: contentStart..<xml.endIndex) else {
            return nil
        }

        return String(xml[contentStart..<closeRange.lowerBound])
    }

    private func extractXMLAttribute(from xml: String, tag: String, attribute: String) -> String? {
        let pattern = "<\(tag)"
        guard let tagStart = xml.range(of: pattern) else { return nil }
        guard let tagEnd = xml[tagStart.upperBound...].firstIndex(of: ">") else { return nil }
        let tagContent = xml[tagStart.upperBound..<tagEnd]

        let attrPattern = "\(attribute)=\""
        guard let attrStart = tagContent.range(of: attrPattern) else { return nil }
        let valueStart = attrStart.upperBound
        guard let valueEnd = tagContent[valueStart...].firstIndex(of: "\"") else { return nil }

        return String(tagContent[valueStart..<valueEnd])
    }

    private func escapeXML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
