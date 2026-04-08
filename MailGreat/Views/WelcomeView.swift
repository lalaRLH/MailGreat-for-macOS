import SwiftUI

/// Welcome screen with app introduction and resume option.
struct WelcomeView: View {
    @Bindable var viewModel: MigrationViewModel

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // App icon and title
            VStack(spacing: 16) {
                Image(systemName: "envelope.arrow.triangle.branch.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.accent)

                Text("MailGreat")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Fast, reliable email migration for Mac")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                FeatureRow(
                    icon: "bolt.fill",
                    title: "Fast Migration",
                    subtitle: "Direct server-to-server copy — faster than traditional mail clients"
                )
                FeatureRow(
                    icon: "arrow.clockwise",
                    title: "Resume Anytime",
                    subtitle: "Pause, quit, or crash — pick up exactly where you left off"
                )
                FeatureRow(
                    icon: "doc.on.doc.fill",
                    title: "Full Fidelity",
                    subtitle: "All headers, metadata, flags, and folder structure preserved"
                )
                FeatureRow(
                    icon: "server.rack",
                    title: "Multi-Protocol",
                    subtitle: "IMAP, POP3, and Exchange Web Services support"
                )
            }
            .padding(.horizontal, 40)

            // Resume banner
            if viewModel.hasResumableState {
                GroupBox {
                    HStack {
                        Image(systemName: "arrow.uturn.forward.circle.fill")
                            .foregroundStyle(.orange)
                            .font(.title2)

                        VStack(alignment: .leading) {
                            Text("Previous Migration Found")
                                .fontWeight(.medium)
                            if let state = viewModel.resumableState {
                                Text("\(state.statistics.migratedMessages) of \(state.statistics.totalMessages) messages migrated")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()

                        Button("Resume") {
                            viewModel.resumeFromSavedState()
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Discard") {
                            viewModel.discardResumableState()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(4)
                }
                .padding(.horizontal, 40)
            }

            Spacer()

            // Get Started button
            Button(action: { viewModel.goNext() }) {
                Text("Get Started")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)

            Spacer()
                .frame(height: 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A single feature highlight row.
private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.accent)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
