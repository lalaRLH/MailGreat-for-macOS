import SwiftUI

/// Live migration progress view with per-folder detail, speed, and controls.
struct MigrationProgressView: View {
    @Bindable var viewModel: MigrationViewModel

    var body: some View {
        VStack(spacing: 0) {
            // Header with overall progress
            VStack(spacing: 16) {
                Label("Migration in Progress", systemImage: "arrow.triangle.2.circlepath")
                    .font(.title2)
                    .fontWeight(.semibold)

                if let engine = viewModel.engine {
                    // Overall progress bar
                    VStack(spacing: 8) {
                        ProgressView(value: engine.state.statistics.overallProgress) {
                            HStack {
                                Text("Overall Progress")
                                    .font(.callout)
                                Spacer()
                                Text("\(Int(engine.state.statistics.overallProgress * 100))%")
                                    .font(.callout)
                                    .fontWeight(.medium)
                                    .monospacedDigit()
                            }
                        }
                        .tint(progressTint)

                        // Stats row
                        HStack(spacing: 24) {
                            StatLabel(
                                icon: "envelope.fill",
                                label: "Messages",
                                value: "\(engine.state.statistics.migratedMessages) / \(engine.state.statistics.totalMessages)"
                            )
                            StatLabel(
                                icon: "folder.fill",
                                label: "Folders",
                                value: "\(engine.state.statistics.completedFolders) / \(engine.state.statistics.totalFolders)"
                            )
                            StatLabel(
                                icon: "speedometer",
                                label: "Speed",
                                value: String(format: "%.1f msg/s", engine.speed)
                            )
                            StatLabel(
                                icon: "externaldrive.fill",
                                label: "Transferred",
                                value: formatBytes(engine.state.statistics.bytesTransferred)
                            )
                            if engine.state.statistics.failedMessages > 0 {
                                StatLabel(
                                    icon: "exclamationmark.triangle.fill",
                                    label: "Failed",
                                    value: "\(engine.state.statistics.failedMessages)"
                                )
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            .padding(24)

            Divider()

            // Per-folder progress
            if let engine = viewModel.engine {
                List {
                    ForEach(engine.state.folderStates) { folderState in
                        FolderProgressRow(
                            folderState: folderState,
                            isCurrent: folderState.sourcePath == engine.currentFolder
                        )
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }

            Divider()

            // Controls
            HStack(spacing: 16) {
                // Status text
                Group {
                    if let engine = viewModel.engine {
                        switch engine.state.status {
                        case .inProgress:
                            if engine.isPaused {
                                Label("Paused", systemImage: "pause.circle.fill")
                                    .foregroundStyle(.orange)
                            } else {
                                Label("Migrating: \(engine.currentFolder)", systemImage: "circle.fill")
                                    .foregroundStyle(.green)
                            }
                        case .completed:
                            Label("Migration Complete", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed:
                            Label("Migration Failed", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        case .cancelled:
                            Label("Cancelled", systemImage: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        default:
                            Text("")
                        }
                    }
                }
                .font(.callout)

                Spacer()

                // Error log toggle
                if let engine = viewModel.engine, !engine.errors.isEmpty {
                    Button {
                        // Would show error sheet
                    } label: {
                        Label("\(engine.errors.count) Errors", systemImage: "exclamationmark.triangle")
                    }
                    .buttonStyle(.bordered)
                }

                // Pause / Resume
                if let engine = viewModel.engine, engine.isRunning {
                    if engine.isPaused {
                        Button {
                            viewModel.resumeMigration()
                        } label: {
                            Label("Resume", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    } else {
                        Button {
                            viewModel.pauseMigration()
                        } label: {
                            Label("Pause", systemImage: "pause.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                // Cancel
                if let engine = viewModel.engine, engine.isRunning {
                    Button(role: .destructive) {
                        viewModel.cancelMigration()
                    } label: {
                        Label("Cancel", systemImage: "xmark")
                    }
                    .buttonStyle(.bordered)
                }

                // Continue to completion
                if viewModel.engine?.state.status == .completed {
                    Button("Continue") {
                        viewModel.goNext()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(16)
        }
        .onAppear {
            if viewModel.engine == nil || viewModel.engine?.isRunning == false {
                viewModel.startMigration()
            }
        }
    }

    private var progressTint: Color {
        guard let engine = viewModel.engine else { return .accentColor }
        if engine.isPaused { return .orange }
        if engine.state.status == .completed { return .green }
        if engine.state.status == .failed { return .red }
        return .accentColor
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Folder Progress Row

private struct FolderProgressRow: View {
    let folderState: FolderMigrationState
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            Group {
                switch folderState.status {
                case .completed:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .inProgress:
                    ProgressView()
                        .controlSize(.small)
                case .failed:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                default:
                    Image(systemName: "circle")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 20)

            // Folder info
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(folderState.sourcePath)
                        .fontWeight(isCurrent ? .semibold : .regular)
                    Image(systemName: "arrow.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(folderState.destinationPath)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: folderState.progress)
                    .tint(folderState.status == .completed ? .green : .accentColor)
            }

            Spacer()

            // Count
            Text("\(folderState.migratedCount) / \(folderState.totalMessages)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            // Failed count
            if folderState.failedCount > 0 {
                Text("\(folderState.failedCount) failed")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
        .background(isCurrent ? Color.accentColor.opacity(0.05) : Color.clear)
    }
}

// MARK: - Stat Label

private struct StatLabel: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
            Text(label + ":")
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }
}
