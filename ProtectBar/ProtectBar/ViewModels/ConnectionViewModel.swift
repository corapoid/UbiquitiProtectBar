import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.protectbar.app", category: "Connection")

@MainActor
final class ConnectionViewModel: ObservableObject {

    @Published var isConnecting = false
    @Published var isConnected = false
    @Published var errorMessage: String?
    @Published var cameraCount: Int = 0

    private let apiClient: ProtectAPIClient
    private var reconnectTask: Task<Void, Never>?
    private var reconnectAttempts = 0
    private let maxReconnectAttempts = 10
    private var lastSettings: AppSettings?

    init(apiClient: ProtectAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Connect

    func connect(settings: AppSettings) async {
        guard !settings.normalizedHost.isEmpty else {
            errorMessage = "Please enter the NVR address"
            return
        }

        lastSettings = settings
        isConnecting = true
        errorMessage = nil

        do {
            if settings.useAPIKey {
                guard let apiKey = KeychainManager.loadAPIKey() else {
                    errorMessage = "No API key saved. Please configure in Settings."
                    isConnecting = false
                    return
                }

                try await apiClient.loginWithAPIKey(
                    baseURL: settings.baseURL,
                    apiKey: apiKey
                )
            } else {
                guard let credentials = KeychainManager.loadCredentials() else {
                    errorMessage = "No credentials saved. Please configure in Settings."
                    isConnecting = false
                    return
                }

                try await apiClient.login(
                    baseURL: settings.baseURL,
                    username: credentials.username,
                    password: credentials.password
                )

                _ = try await apiClient.fetchBootstrap(baseURL: settings.baseURL)
            }

            cameraCount = apiClient.cameras.count
            isConnected = true
            reconnectAttempts = 0
            logger.info("Connected successfully. Found \(self.cameraCount) cameras")
            startHealthCheck(settings: settings)
        } catch {
            logger.error("Connection failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            isConnected = false
            scheduleReconnect(settings: settings)
        }

        isConnecting = false
    }

    // MARK: - Disconnect

    func disconnect() {
        stopReconnect()
        apiClient.disconnect()
        isConnected = false
        cameraCount = 0
        lastSettings = nil
    }

    // MARK: - Test Connection

    func testConnection(host: String, username: String, password: String) async -> (success: Bool, message: String) {
        let baseURL = "https://\(host)"
        let result = await apiClient.testConnection(baseURL: baseURL, username: username, password: password)

        switch result {
        case .success(let count):
            return (true, "Connected! Found \(count) camera(s).")
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }

    func testConnectionWithAPIKey(host: String, apiKey: String) async -> (success: Bool, message: String) {
        let baseURL = "https://\(host)"
        let result = await apiClient.testConnectionWithAPIKey(baseURL: baseURL, apiKey: apiKey)

        switch result {
        case .success(let count):
            return (true, "Connected! Found \(count) camera(s).")
        case .failure(let error):
            return (false, error.localizedDescription)
        }
    }

    // MARK: - Auto Reconnect

    private func scheduleReconnect(settings: AppSettings) {
        guard reconnectAttempts < maxReconnectAttempts else {
            errorMessage = "Failed to reconnect after \(maxReconnectAttempts) attempts"
            return
        }

        reconnectAttempts += 1
        let delay = min(pow(2.0, Double(reconnectAttempts)), 60.0)

        reconnectTask = Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await connect(settings: settings)
        }
    }

    private func startHealthCheck(settings: AppSettings) {
        stopReconnect()

        reconnectTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                guard !Task.isCancelled else { return }

                do {
                    _ = try await apiClient.fetchBootstrap(baseURL: settings.baseURL)
                } catch {
                    isConnected = false
                    errorMessage = "Connection lost. Reconnecting..."
                    reconnectAttempts = 0
                    await connect(settings: settings)
                    return
                }
            }
        }
    }

    private func stopReconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
    }
}
