import SwiftUI

/// MailGreat — Fast email migration for Mac.
@main
struct MailGreatApp: App {
    @State private var viewModel = MigrationViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified(showsTitle: true))
        .defaultSize(width: 960, height: 700)
        .commands {
            // Standard macOS menus
            CommandGroup(replacing: .newItem) { }

            CommandMenu("Migration") {
                Button("Start Migration") {
                    viewModel.startMigration()
                }
                .keyboardShortcut("r", modifiers: [.command])
                .disabled(viewModel.engine?.isRunning == true)

                Button("Pause") {
                    viewModel.pauseMigration()
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .disabled(viewModel.engine?.isRunning != true || viewModel.engine?.isPaused == true)

                Button("Resume") {
                    viewModel.resumeMigration()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(viewModel.engine?.isPaused != true)

                Divider()

                Button("Cancel Migration") {
                    viewModel.cancelMigration()
                }
                .disabled(viewModel.engine?.isRunning != true)
            }
        }

        Settings {
            SettingsView()
        }
    }
}
