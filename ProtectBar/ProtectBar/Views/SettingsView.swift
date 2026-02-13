import SwiftUI

/// Settings view for configuring NVR connection
struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var connectionVM: ConnectionViewModel
    var onDismiss: (() -> Void)?

    @State private var host: String = ""
    @State private var authMethod: AuthMethod = .apiKey
    @State private var apiKey: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var testResult: String?
    @State private var testSuccess: Bool = false
    @State private var isTesting: Bool = false
    @State private var showSecret: Bool = false
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { /* handled by parent */ }, label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                })
                .buttonStyle(.plain)
                .hidden() // placeholder for layout

                Spacer()
                Text(L10n.Settings.title)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Connection Type
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.Settings.connectionType, systemImage: "network")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $settings.connectionTypeRaw) {
                            ForEach(ConnectionType.allCases, id: \.rawValue) { type in
                                Text(type.displayName).tag(type.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    // NVR Address
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.Settings.nvrAddress, systemImage: "server.rack")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        TextField(L10n.Settings.nvrAddressPlaceholder, text: $host)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }

                    // Authentication Method
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.Settings.authentication, systemImage: "key")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $authMethod) {
                            ForEach(AuthMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        if authMethod == .apiKey {
                            // API Key input
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    if showSecret {
                                        TextField(L10n.Settings.apiKey, text: $apiKey)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.caption, design: .monospaced))
                                    } else {
                                        SecureField(L10n.Settings.apiKey, text: $apiKey)
                                            .textFieldStyle(.roundedBorder)
                                    }
                                    Button(action: { showSecret.toggle() }, label: {
                                        Image(systemName: showSecret ? "eye.slash" : "eye")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    })
                                    .buttonStyle(.plain)
                                }

                                Text(L10n.Settings.apiKeyHint)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        } else {
                            // Username/Password
                            TextField(L10n.Settings.username, text: $username)
                                .textFieldStyle(.roundedBorder)

                            HStack {
                                if showSecret {
                                    TextField(L10n.Settings.password, text: $password)
                                        .textFieldStyle(.roundedBorder)
                                } else {
                                    SecureField(L10n.Settings.password, text: $password)
                                        .textFieldStyle(.roundedBorder)
                                }
                                Button(action: { showSecret.toggle() }, label: {
                                    Image(systemName: showSecret ? "eye.slash" : "eye")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                })
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Stream Quality
                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.Settings.streamQuality, systemImage: "gauge.medium")
                            .font(.subheadline)
                            .fontWeight(.medium)

                        Picker("", selection: $settings.streamQualityRaw) {
                            ForEach(StreamQuality.allCases, id: \.rawValue) { quality in
                                Text(quality.displayName).tag(quality.rawValue)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()

                        Text(L10n.Settings.streamQualityHint)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Divider()

                    // Error display
                    if let error = saveError {
                        InlineErrorView(error)
                    }

                    // Test & Save
                    VStack(spacing: 8) {
                        if let result = testResult {
                            HStack {
                                Image(systemName: testSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(testSuccess ? .green : .red)
                                Text(result)
                                    .font(.caption)
                                    .foregroundColor(testSuccess ? .green : .red)
                            }
                        }

                        HStack(spacing: 8) {
                            Button(L10n.Settings.testConnection) {
                                testConnection()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(isTesting || !isFormValid)

                            Button(L10n.Settings.saveConnect) {
                                saveAndConnect()
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(!isFormValid)
                        }

                        if settings.isConfigured {
                            Button(L10n.Settings.disconnectClear) {
                                clearSettings()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.mini)
                            .foregroundColor(.red)
                        }
                    }
                }
                .padding(16)
            }
        }
        .onAppear {
            loadCurrentSettings()
        }
    }

    // MARK: - Computed

    private var isFormValid: Bool {
        guard !host.isEmpty else { return false }

        if authMethod == .apiKey {
            return !apiKey.isEmpty
        } else {
            return !username.isEmpty && !password.isEmpty
        }
    }

    // MARK: - Actions

    private func loadCurrentSettings() {
        host = settings.normalizedHost
        
        // Respect the saved auth method preference
        if settings.useAPIKey {
            authMethod = .apiKey
            if let key = KeychainManager.loadAPIKey() {
                apiKey = key
            }
        } else {
            authMethod = .credentials
            if let creds = KeychainManager.loadCredentials() {
                username = creds.username
                password = creds.password
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let cleanHost = cleanHostInput(host)

        Task {
            let result: (success: Bool, message: String)

            if authMethod == .apiKey {
                result = await connectionVM.testConnectionWithAPIKey(
                    host: cleanHost,
                    apiKey: apiKey
                )
            } else {
                result = await connectionVM.testConnection(
                    host: cleanHost,
                    username: username,
                    password: password
                )
            }

            testResult = result.message
            testSuccess = result.success
            isTesting = false
        }
    }

    private func saveAndConnect() {
        saveError = nil
        let cleanHost = cleanHostInput(host)
        settings.hostAddress = cleanHost

        do {
            if authMethod == .apiKey {
                try KeychainManager.saveAPIKey(apiKey)
                KeychainManager.deleteCredentials() // Clear old credentials
                settings.useAPIKey = true
            } else {
                try KeychainManager.saveCredentials(username: username, password: password)
                KeychainManager.deleteAPIKey() // Clear old API key
                settings.useAPIKey = false
            }
        } catch {
            saveError = L10n.Error.connectionFailed(error.localizedDescription)
            return
        }

        settings.isConfigured = true

        Task {
            await connectionVM.connect(settings: settings)
            if connectionVM.isConnected {
                onDismiss?()
            }
        }
    }

    private func clearSettings() {
        connectionVM.disconnect()
        KeychainManager.deleteCredentials()
        KeychainManager.deleteAPIKey()
        settings.hostAddress = ""
        settings.isConfigured = false
        settings.useAPIKey = true
        host = ""
        apiKey = ""
        username = ""
        password = ""
        testResult = nil
    }

    private func cleanHostInput(_ input: String) -> String {
        var h = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if h.hasPrefix("https://") { h = String(h.dropFirst(8)) }
        if h.hasPrefix("http://") { h = String(h.dropFirst(7)) }
        if h.hasSuffix("/") { h = String(h.dropLast()) }
        return h
    }
}
