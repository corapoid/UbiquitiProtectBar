import Foundation
import SwiftUI

@MainActor
final class CameraGridViewModel: ObservableObject {

    @Published var cameras: [Camera] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastError: Error?
    @Published var selectedCamera: Camera?

    private let apiClient: ProtectAPIClient
    private var refreshTask: Task<Void, Never>?

    init(apiClient: ProtectAPIClient) {
        self.apiClient = apiClient
    }

    // MARK: - Load cameras

    func loadCameras(settings: AppSettings) async {
        isLoading = true
        errorMessage = nil
        lastError = nil

        do {
            let bootstrap = try await apiClient.fetchBootstrap(baseURL: settings.baseURL)
            cameras = bootstrap.cameras.filter { $0.isConnected && $0.hasRTSP }
        } catch {
            lastError = error
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    // MARK: - Auto Refresh

    func startAutoRefresh(settings: AppSettings, interval: TimeInterval = 30) {
        stopAutoRefresh()
        refreshTask = Task {
            while !Task.isCancelled {
                await loadCameras(settings: settings)
                try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    // MARK: - RTSP URL

    func rtspURL(for camera: Camera, settings: AppSettings) -> String? {
        let quality = settings.streamQuality
        return apiClient.rtspURL(host: settings.normalizedHost, camera: camera, quality: quality)
    }

    // MARK: - Selection

    func selectCamera(_ camera: Camera) {
        selectedCamera = camera
    }

    func clearSelection() {
        selectedCamera = nil
    }
}
