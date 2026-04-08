import SwiftUI

/// Main content view with sidebar navigation and step detail.
struct ContentView: View {
    @Bindable var viewModel: MigrationViewModel

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detailView
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        toolbarItems
                    }
                }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(MigrationStep.allCases, selection: Binding(
            get: { viewModel.currentStep },
            set: { viewModel.goToStep($0) }
        )) { step in
            StepRow(
                step: step,
                isCompleted: viewModel.completedSteps.contains(step),
                isCurrent: viewModel.currentStep == step,
                isAccessible: viewModel.completedSteps.contains(step) || step.rawValue <= viewModel.currentStep.rawValue
            )
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        .safeAreaInset(edge: .bottom) {
            // Connection status footer
            VStack(spacing: 6) {
                Divider()
                ConnectionIndicator(
                    label: "Source",
                    status: viewModel.sourceConnectionStatus
                )
                ConnectionIndicator(
                    label: "Destination",
                    status: viewModel.destinationConnectionStatus
                )
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    // MARK: - Detail View

    @ViewBuilder
    private var detailView: some View {
        switch viewModel.currentStep {
        case .welcome:
            WelcomeView(viewModel: viewModel)
        case .sourceAccount:
            SourceAccountView(viewModel: viewModel)
        case .destinationAccount:
            DestinationAccountView(viewModel: viewModel)
        case .folderMapping:
            FolderMappingView(viewModel: viewModel)
        case .migration:
            MigrationProgressView(viewModel: viewModel)
        case .completion:
            CompletionView(viewModel: viewModel)
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var toolbarItems: some View {
        if viewModel.canGoBack {
            Button {
                viewModel.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
        }

        if viewModel.canGoNext && viewModel.currentStep != .welcome {
            Button {
                viewModel.goNext()
            } label: {
                Label("Next", systemImage: "chevron.right")
            }
            .keyboardShortcut(.defaultAction)
        }
    }
}

// MARK: - Step Row

private struct StepRow: View {
    let step: MigrationStep
    let isCompleted: Bool
    let isCurrent: Bool
    let isAccessible: Bool

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(circleColor)
                    .frame(width: 26, height: 26)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(isCurrent ? .white : .secondary)
                }
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(step.title)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .foregroundStyle(isAccessible ? .primary : .tertiary)
            }

            Spacer()

            if isCurrent {
                Image(systemName: step.icon)
                    .foregroundStyle(.accent)
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .opacity(isAccessible ? 1 : 0.5)
    }

    private var circleColor: Color {
        if isCompleted { return .green }
        if isCurrent { return .accentColor }
        return Color.secondary.opacity(0.2)
    }
}

// MARK: - Connection Indicator

private struct ConnectionIndicator: View {
    let label: String
    let status: ConnectionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 8, height: 8)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Spacer()
            Text(status.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
