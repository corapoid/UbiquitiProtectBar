import Foundation
import AppKit
import AVFoundation

/// Manages RTSP stream playback using VLCKit (or fallback to snapshot polling)
/// VLCKit must be installed separately — this provides the integration layer.
///
/// Since VLCKit requires a separate framework installation, this implementation
/// uses a process-based approach with ffmpeg/ffplay as a lightweight alternative,
/// and provides snapshot-based fallback when neither is available.
@MainActor
final class RTSPStreamManager: ObservableObject {

    enum StreamState: Sendable {
        case idle
        case connecting
        case playing
        case error(String)
    }

    @Published var state: StreamState = .idle
    @Published var currentFrame: NSImage?

    private var snapshotTimer: Timer?
    private var isActive = false
    private var isPaused = false
    
    // Snapshot stream params for resume
    private var savedApiClient: ProtectAPIClient?
    private var savedBaseURL: String?
    private var savedCameraId: String?
    private var savedInterval: TimeInterval = 1.0

    // MARK: - Snapshot-based streaming (fallback)

    /// Start periodic snapshot fetching as RTSP fallback
    func startSnapshotStream(
        apiClient: ProtectAPIClient,
        baseURL: String,
        cameraId: String,
        interval: TimeInterval = 1.0
    ) {
        stopStream()
        isActive = true
        isPaused = false
        state = .connecting
        
        // Save params for resume
        savedApiClient = apiClient
        savedBaseURL = baseURL
        savedCameraId = cameraId
        savedInterval = interval

        snapshotTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }
                do {
                    let data = try await apiClient.fetchSnapshot(
                        baseURL: baseURL,
                        cameraId: cameraId,
                        width: AppConstants.snapshotWidth,
                        height: AppConstants.snapshotHeight
                    )
                    if let image = NSImage(data: data) {
                        self.currentFrame = image
                        self.state = .playing
                    }
                } catch {
                    self.state = .error(error.localizedDescription)
                }
            }
        }

        // Fire immediately
        Task {
            do {
                let data = try await apiClient.fetchSnapshot(
                    baseURL: baseURL,
                    cameraId: cameraId,
                    width: AppConstants.snapshotWidth,
                    height: AppConstants.snapshotHeight
                )
                if let image = NSImage(data: data) {
                    currentFrame = image
                    state = .playing
                }
            } catch {
                state = .error(error.localizedDescription)
            }
        }
    }

    // MARK: - Stop

    func stopStream() {
        isActive = false
        isPaused = false
        snapshotTimer?.invalidate()
        snapshotTimer = nil
        state = .idle
        currentFrame = nil
        
        // Clear saved params
        savedApiClient = nil
        savedBaseURL = nil
        savedCameraId = nil
    }
    
    // MARK: - Pause/Resume
    
    /// Pause snapshot fetching (keeps state for resume)
    func pauseStream() {
        guard isActive, !isPaused else { return }
        isPaused = true
        snapshotTimer?.invalidate()
        snapshotTimer = nil
    }
    
    /// Resume snapshot fetching
    func resumeStream() {
        guard isActive, isPaused,
              let apiClient = savedApiClient,
              let baseURL = savedBaseURL,
              let cameraId = savedCameraId else { return }
        
        isPaused = false
        
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: savedInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isActive, !self.isPaused else { return }
                do {
                    let data = try await apiClient.fetchSnapshot(
                        baseURL: baseURL,
                        cameraId: cameraId,
                        width: AppConstants.snapshotWidth,
                        height: AppConstants.snapshotHeight
                    )
                    if let image = NSImage(data: data) {
                        self.currentFrame = image
                        self.state = .playing
                    }
                } catch {
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    deinit {
        snapshotTimer?.invalidate()
    }
}
