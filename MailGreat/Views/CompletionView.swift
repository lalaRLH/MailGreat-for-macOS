import SwiftUI

/// Migration completion summary view.
struct CompletionView: View {
    @Bindable var viewModel: MigrationViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Success icon
            Image(systemName: statusIcon)
                .font(.system(size: 56))
                .foregroundStyle(statusColor)

            // Title
            VStack(spacing: 8) {
                Text(statusTitle)
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text(statusSubtitle)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            // Statistics
            if let engine = viewModel.engine {
                GroupBox("Migration Summary") {
                    Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 10) {
                        GridRow {
                            SummaryItem(icon: "envelope.fill", label: "Messages Migrated",
                                        value: "\(engine.state.statistics.migratedMessages)")
                            SummaryItem(icon: "folder.fill", label: "Folders Processed",
                                        value: "\(engine.state.statistics.completedFolders) of \(engine.state.statistics.totalFolders)")
                        }
                        GridRow {
                            SummaryItem(icon: "externaldrive.fill", label: "Data Transferred",
                                        value: formatBytes(engine.state.statistics.bytesTransferred))
                            SummaryItem(icon: "clock.fill", label: "Duration",
                                        value: formatDuration(engine.state))
                        }
                        if engine.state.statistics.failedMessages > 0 {
                            GridRow {
                                SummaryItem(icon: "exclamationmark.triangle.fill", label: "Failed Messages",
                                            value: "\(engine.state.statistics.failedMessages)")
                                SummaryItem(icon: "speedometer", label: "Average Speed",
                                            value: String(format: "%.1f msg/s", averageSpeed(engine.state)))
                            }
                        } else {
                            GridRow {
                                SummaryItem(icon: "speedometer", label: "Average Speed",
                                            value: String(format: "%.1f msg/s", averageSpeed(engine.state)))
                                Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                            }
                        }
                    }
                    .padding(12)
                }
                .frame(maxWidth: 500)

                // Per-folder summary
                if !engine.state.folderStates.isEmpty {
                    GroupBox("Folder Details") {
                        VStack(spacing: 0) {
                            ForEach(engine.state.folderStates) { folderState in
                                HStack {
                                    Image(systemName: folderState.status == .completed
                                          ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                                        .foregroundStyle(folderState.status == .completed ? .green : .orange)

                                    Text(folderState.sourcePath)
                                        .fontWeight(.medium)

                                    Spacer()

                                    Text("\(folderState.migratedCount) / \(folderState.totalMessages)")
                                        .font(.callout)
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                            }
                        }
                    }
                    .frame(maxWidth: 500)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 16) {
                Button("Start New Migration") {
                    viewModel.discardResumableState()
                    viewModel.currentStep = .welcome
                    viewModel.completedSteps = []
                    viewModel.engine = nil
                    viewModel.sourceConnectionStatus = .disconnected
                    viewModel.destinationConnectionStatus = .disconnected
                }
                .buttonStyle(.bordered)

                Button("Quit") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderedProminent)
            }

            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    // MARK: - Status Helpers

    private var statusIcon: String {
        guard let engine = viewModel.engine else { return "questionmark.circle" }
        switch engine.state.status {
        case .completed:
            return engine.state.statistics.failedMessages > 0
                ? "checkmark.circle.trianglebadge.exclamationmark" : "checkmark.seal.fill"
        case .cancelled: return "xmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        default: return "checkmark.seal.fill"
        }
    }

    private var statusColor: Color {
        guard let engine = viewModel.engine else { return .secondary }
        switch engine.state.status {
        case .completed:
            return engine.state.statistics.failedMessages > 0 ? .orange : .green
        case .cancelled: return .secondary
        case .failed: return .red
        default: return .green
        }
    }

    private var statusTitle: String {
        guard let engine = viewModel.engine else { return "Done" }
        switch engine.state.status {
        case .completed:
            return engine.state.statistics.failedMessages > 0
                ? "Migration Completed with Warnings" : "Migration Complete"
        case .cancelled: return "Migration Cancelled"
        case .failed: return "Migration Failed"
        default: return "Done"
        }
    }

    private var statusSubtitle: String {
        guard let engine = viewModel.engine else { return "" }
        switch engine.state.status {
        case .completed:
            return engine.state.statistics.failedMessages > 0
                ? "\(engine.state.statistics.failedMessages) messages could not be migrated."
                : "All emails have been successfully migrated."
        case .cancelled:
            return "Migration was cancelled. Progress has been saved and can be resumed."
        case .failed:
            return "An error occurred during migration. Progress has been saved."
        default: return ""
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .binary)
    }

    private func formatDuration(_ state: MigrationState) -> String {
        let duration = state.lastUpdatedAt.timeIntervalSince(state.startedAt)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute, .second]
        formatter.unitsStyle = .abbreviated
        return formatter.string(from: duration) ?? "—"
    }

    private func averageSpeed(_ state: MigrationState) -> Double {
        let duration = state.lastUpdatedAt.timeIntervalSince(state.startedAt)
        guard duration > 0 else { return 0 }
        return Double(state.statistics.migratedMessages) / duration
    }
}

// MARK: - Summary Item

private struct SummaryItem: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.accent)
                .frame(width: 20)
            VStack(alignment: .leading) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
    }
}
