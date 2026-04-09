import Foundation

/// Maps source server folders to appropriate destination folder names.
/// Handles differences in folder naming conventions between providers.
struct FolderMapper {

    /// Generate default folder mappings from source folders.
    static func generateMappings(
        sourceFolders: [EmailFolder],
        destinationFolders: [EmailFolder]
    ) -> [FolderMapping] {
        sourceFolders.map { source in
            let destPath = mapFolderPath(source: source, existingDestFolders: destinationFolders)
            return FolderMapping(source: source, destinationPath: destPath)
        }
    }

    /// Determine the best destination path for a source folder.
    static func mapFolderPath(
        source: EmailFolder,
        existingDestFolders: [EmailFolder]
    ) -> String {
        let sourceType = source.folderType

        // For well-known folder types, find the matching destination folder
        if sourceType != .custom {
            if let match = existingDestFolders.first(where: { $0.folderType == sourceType }) {
                return match.path
            }
            // Use canonical names if no match exists on destination
            return canonicalName(for: sourceType)
        }

        // For custom folders, try to find an exact name match first
        if let exactMatch = existingDestFolders.first(where: {
            $0.name.lowercased() == source.name.lowercased()
        }) {
            return exactMatch.path
        }

        // Otherwise, use the source path directly (will be created)
        return source.path
    }

    /// Canonical folder name for a well-known folder type.
    static func canonicalName(for type: WellKnownFolder) -> String {
        switch type {
        case .inbox: return "INBOX"
        case .sent: return "Sent"
        case .drafts: return "Drafts"
        case .trash: return "Trash"
        case .junk: return "Junk"
        case .archive: return "Archive"
        case .custom: return ""
        }
    }

    /// Icon name (SF Symbol) for a folder type.
    static func iconName(for type: WellKnownFolder) -> String {
        switch type {
        case .inbox: return "tray.fill"
        case .sent: return "paperplane.fill"
        case .drafts: return "doc.fill"
        case .trash: return "trash.fill"
        case .junk: return "xmark.bin.fill"
        case .archive: return "archivebox.fill"
        case .custom: return "folder.fill"
        }
    }
}
