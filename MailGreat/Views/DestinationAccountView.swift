import SwiftUI

/// Destination account configuration view.
struct DestinationAccountView: View {
    @Bindable var viewModel: MigrationViewModel
    @State private var password = ""
    @State private var showPassword = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Label("Destination Account", systemImage: "arrow.left.doc.on.clipboard")
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text("Configure the email account you want to migrate to.")
                        .foregroundStyle(.secondary)
                }

                // Protocol picker
                GroupBox("Connection") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Protocol", selection: $viewModel.destinationAccount.mailProtocol) {
                            // POP3 can't be a destination (no upload support)
                            Text(MailProtocol.imap.rawValue).tag(MailProtocol.imap)
                            Text(MailProtocol.exchange.rawValue).tag(MailProtocol.exchange)
                        }
                        .onChange(of: viewModel.destinationAccount.mailProtocol) { _, newValue in
                            viewModel.destinationAccount.port = newValue.defaultPort
                            viewModel.destinationAccount.useTLS = newValue.defaultUseTLS
                        }

                        TextField("Server Hostname", text: $viewModel.destinationAccount.hostname)
                            .textFieldStyle(.roundedBorder)

                        HStack {
                            TextField("Port", value: $viewModel.destinationAccount.port, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 100)

                            Toggle("Use TLS", isOn: $viewModel.destinationAccount.useTLS)
                        }
                    }
                    .padding(8)
                }

                // Credentials
                GroupBox("Authentication") {
                    VStack(alignment: .leading, spacing: 12) {
                        Picker("Method", selection: $viewModel.destinationAccount.authMethod) {
                            ForEach(AuthMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }

                        TextField("Username / Email", text: $viewModel.destinationAccount.username)
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

                        if viewModel.destinationAccount.authMethod == .oauth2 {
                            Text("Enter your OAuth2 access token in the password field.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(8)
                }

                // Connection status
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.destinationConnectionStatus.icon)
                            .foregroundStyle(viewModel.destinationConnectionStatus.color)
                        Text(viewModel.destinationConnectionStatus.label)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if viewModel.isConnectingDestination {
                        ProgressView()
                            .controlSize(.small)
                            .padding(.trailing, 8)
                    }

                    Button(viewModel.destinationConnectionStatus == .connected ? "Reconnect" : "Connect & Verify") {
                        viewModel.savePassword(password, for: viewModel.destinationAccount)
                        Task { await viewModel.connectDestination() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        viewModel.destinationAccount.hostname.isEmpty
                        || viewModel.destinationAccount.username.isEmpty
                        || password.isEmpty
                        || viewModel.isConnectingDestination
                    )
                }

                // Error display
                if let error = viewModel.connectionError,
                   viewModel.destinationConnectionStatus == .error {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                }

                // Connected summary
                if viewModel.destinationConnectionStatus == .connected {
                    GroupBox("Existing Folders") {
                        VStack(alignment: .leading, spacing: 6) {
                            if viewModel.destinationFolders.isEmpty {
                                Text("No existing folders found — they will be created during migration.")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            } else {
                                ForEach(viewModel.destinationFolders) { folder in
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
                        }
                        .padding(8)
                    }
                }
            }
            .padding(24)
        }
        .onAppear {
            if let saved = KeychainHelper.loadPassword(for: viewModel.destinationAccount.keychainKey) {
                password = saved
            }
        }
    }
}
