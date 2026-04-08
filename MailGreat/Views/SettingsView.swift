import SwiftUI

/// App settings accessible via Cmd+, (standard macOS settings window).
struct SettingsView: View {
    @AppStorage("maxConcurrency") private var maxConcurrency = 3
    @AppStorage("batchSize") private var batchSize = 20
    @AppStorage("throttleDelay") private var throttleDelay = 0
    @AppStorage("autoResume") private var autoResume = true
    @AppStorage("cpuPriority") private var cpuPriority = "Medium"
    @AppStorage("showNotification") private var showNotification = true

    var body: some View {
        TabView {
            performanceTab
                .tabItem {
                    Label("Performance", systemImage: "gauge.with.dots.needle.67percent")
                }

            generalTab
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
        }
        .frame(width: 450, height: 320)
    }

    // MARK: - Performance Tab

    private var performanceTab: some View {
        Form {
            Section("Connection") {
                Stepper(value: $maxConcurrency, in: 1...8) {
                    HStack {
                        Text("Max Concurrent Connections")
                        Spacer()
                        Text("\(maxConcurrency)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                Stepper(value: $batchSize, in: 1...100, step: 5) {
                    HStack {
                        Text("Batch Size")
                        Spacer()
                        Text("\(batchSize) messages")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
            }

            Section("Throttling") {
                Picker("Delay Between Messages", selection: $throttleDelay) {
                    Text("None").tag(0)
                    Text("50 ms").tag(50)
                    Text("100 ms").tag(100)
                    Text("250 ms").tag(250)
                    Text("500 ms").tag(500)
                    Text("1 second").tag(1000)
                }

                Picker("CPU Priority", selection: $cpuPriority) {
                    Text("Low (Background)").tag("Low")
                    Text("Medium (Utility)").tag("Medium")
                    Text("High (User Initiated)").tag("High")
                }

                Text("Lower priority and higher delays reduce system impact but slow down migration.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - General Tab

    private var generalTab: some View {
        Form {
            Section("Resume") {
                Toggle("Auto-resume on launch", isOn: $autoResume)
                Text("When enabled, MailGreat will offer to resume an interrupted migration on next launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Notifications") {
                Toggle("Notify when migration completes", isOn: $showNotification)
            }

            Section("Data") {
                Button("Clear Saved Migration Data") {
                    clearMigrationData()
                }
                .foregroundStyle(.red)

                Text("Removes all saved migration progress and state files. Credentials remain in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func clearMigrationData() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("MailGreat", isDirectory: true)
        try? fm.removeItem(at: dir)
    }
}
