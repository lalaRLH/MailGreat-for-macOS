import SwiftUI

/// Source account configuration view.
struct SourceAccountView: View {
    @Bindable var viewModel: MigrationViewModel
    @State private var password = ""
    @State private var showPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("Source Account", systemImage: "arrow.right.doc.on.clipboard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure the email account you want to migrate from.")
                        .foregroundStyle(.secondary)
                }

                // Protocol picker
                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Protocol", selection: $viewModel.sourceAccount.mailProtocol) {
                            ForEach(MailProtocol.allCases) { proto in
                                Text(proto.rawValue).tag(proto)
                            }
                        }
                        .onChange(of: viewModel.sourceAccount.mailProtocol) { _, newValue in
                            viewModel.sourceAccount.port = newValue.defaultPort
                            viewModel.sourceAccount.useTLS = newValue.defaultUseTLS
                        }

                        TextField("Server Hostname", text: $viewModel.sourceAccount.hostname)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            TextField("Port", value: $viewModel.sourceAccount.port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)

                            Toggle("Use TLS", isOn: $viewModel.sourceAccount.useTLS)
                        }
                    }
                    .padding(8)
                }

                // Credentials
                GroupBox("Authentication") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Method", selection: $viewModel.sourceAccount.authMethod) {
                            ForEach(AuthMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }

                        TextField("Username / Email", text: $viewModel.sourceAccount.username)
                            .textFieldStyle(.roundedBorder)
                            .textContentType(.username)

                        HStack {
                            if showPassword {
                                TextField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            } else {
                                SecureField("Password", text: $password)
                                    .textFieldStyle(.roundedBorder)
                            }
                            Button {
                                showPassword.toggle()
                            } label: {
                                Image(systemName: showPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }

                        if viewModel.sourceAccount.authMethod == .oauth2 {
                            Text("Enter your OAuth2 access token in the password field.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // POP3 warning
                if viewModel.sourceAccount.mailProtocol == .pop3 {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        Text("POP3 only supports inbox access. Folders, message flags, and dates may not be preserved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.yellow.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }

                // Connection status and test button
                HStack {
                    // Status indicator
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.sourceConnectionStatus.icon)
                            .foregroundStyle(viewModel.sourceConnectionStatus.color)
                        Text(viewModel.sourceConnectionStatus.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.isConnectingSource {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }

                    Button(viewModel.sourceConnectionStatus == .connected ? "Reconnect" : "Connect & Verify") {
                        viewModel.savePassword(password, for: viewModel.sourceAccount)
                        Task { await viewModel.connectSource() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.sourceAccount.hostname.isEmpty
                        || viewModel.sourceAccount.username.isEmpty
                        || password.isEmpty
                        || viewModel.isConnectingSource
                    )
                }

                // Error display
                if let error = viewModel.connectionError,
                   viewModel.sourceConnectionStatus == .error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                // Folder summary
                if viewModel.sourceConnectionStatus == .connected {
                    GroupBox("Discovered Folders") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(viewModel.sourceFolders) { folder in
                                HStack {
                                    Image(systemName: FolderMapper.iconName(for: folder.folderType))
                                        .foregroundStyle(.accent)
                                        .frame(width: 20)
                                    Text(folder.name)
                                    Spacer()
                                    Text("\(folder.messageCount) messages")
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            // Load saved password if available
            if let saved = KeychainHelper.loadPassword(for: viewModel.sourceAccount.keychainKey) {
                password = saved
            }
        }
    }
}
