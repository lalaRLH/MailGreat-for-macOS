import SwiftUI

/// View for reviewing and customizing folder mappings before migration.
struct FolderMappingView: View {
    @Bindable var viewModel: MigrationViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            VStack(alignment: .leading, spacing: 4) {
                Label("Folder Mapping", systemImage: "folder.badge.gearshape")
                    .font(.title2)
                    .fontWeight(.semibold)
                Text("Review how source folders map to destination folders. Uncheck any you want to skip.")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)

            // Summary
            HStack(spacing: 24) {
                StatBox(
                    label: "Folders",
                    value: "\(viewModel.folderMappings.filter(\.isEnabled).count)",
                    subtitle: "of \(viewModel.folderMappings.count) selected"
                )
                StatBox(
                    label: "Messages",
                    value: "\(totalMessages)",
                    subtitle: "to migrate"
                )
                StatBox(
                    label: "Source",
                    value: viewModel.sourceAccount.mailProtocol.rawValue,
                    subtitle: viewModel.sourceAccount.hostname
                )
                StatBox(
                    label: "Destination",
                    value: viewModel.destinationAccount.mailProtocol.rawValue,
                    subtitle: viewModel.destinationAccount.hostname
                )
            }
            .padding(.horizontal, 24)

            Divider()

            // Folder mapping list
            List {
                ForEach($viewModel.folderMappings) { $mapping in
                    FolderMappingRow(mapping: $mapping)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }

    private var totalMessages: Int {
        viewModel.folderMappings
            .filter(\.isEnabled)
            .reduce(0) { $0 + $1.sourceFolder.messageCount }
    }
}

// MARK: - Folder Mapping Row

private struct FolderMappingRow: View {
    @Binding var mapping: FolderMapping

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $mapping.isEnabled)
                .labelsHidden()
                .toggleStyle(.checkbox)

            // Source folder
            HStack(spacing: 6) {
                Image(systemName: FolderMapper.iconName(for: mapping.sourceFolder.folderType))
                    .foregroundStyle(mapping.isEnabled ? .accent : .secondary)
                VStack(alignment: .leading) {
                    Text(mapping.sourceFolder.name)
                        .fontWeight(.medium)
                    Text("\(mapping.sourceFolder.messageCount) messages")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(minWidth: 150, alignment: .leading)

            Image(systemName: "arrow.right")
                .foregroundStyle(.secondary)

            // Destination folder (editable)
            TextField("Destination", text: $mapping.destinationPath)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 150)

            // Folder type badge
            Text(mapping.sourceFolder.folderType.rawValue)
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    mapping.sourceFolder.folderType == .custom
                    ? Color.purple.opacity(0.15)
                    : Color.blue.opacity(0.15),
                    in: Capsule()
                )
                .foregroundStyle(
                    mapping.sourceFolder.folderType == .custom
                    ? .purple
                    : .blue
                )
        }
        .opacity(mapping.isEnabled ? 1 : 0.5)
        .padding(.vertical, 2)
    }
}

// MARK: - Stat Box

private struct StatBox: View {
    let label: String
    let value: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }
}
