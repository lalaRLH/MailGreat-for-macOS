import Foundation

/// Maps a source folder to a destination folder for migration.
struct FolderMapping: Codable, Identifiable, Hashable {
    var id: String { sourceFolder.path }
    let sourceFolder: EmailFolder
    var destinationPath: String
    var isEnabled: Bool

    init(source: EmailFolder, destinationPath: String, isEnabled: Bool = true) {
        self.sourceFolder = source
        self.destinationPath = destinationPath
        self.isEnabled = isEnabled
    }
}
