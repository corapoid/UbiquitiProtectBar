import SwiftUI
import AppKit

/// A view that displays camera stream — uses MPV for RTSP, falls back to snapshots
struct VLCPlayerView: View {
    let rtspURL: String?
    let cameraName: String
    @ObservedObject var streamManager: RTSPStreamManager
    let apiClient: ProtectAPIClient
    let baseURL: String
    let cameraId: String

    @State private var useMPV: Bool = true

    var body: some View {
        ZStack {
            Color.black

            if let rtspURL, useMPV {
                // RTSP via MPV (primary)
                mpvContent(url: rtspURL)
            } else {
                // Snapshot fallback
                snapshotContent
            }

            // Camera name overlay
            cameraNameOverlay
        }
        .cornerRadius(6)
        .onAppear {
            if rtspURL == nil {
                startSnapshotFallback()
            }
        }
        .onDisappear {
            streamManager.stopStream()
        }
    }

    // MARK: - MPV Content

    @ViewBuilder
    private func mpvContent(url: String) -> some View {
        MPVPlayerNSView(
            rtspURL: url,
            onStateChange: { state in
                Task { @MainActor in
                    streamManager.state = state
                    // If MPV fails, fall back to snapshots
                    if case .error = state {
                        useMPV = false
                        startSnapshotFallback()
                    }
                }
            }
        )

        // State overlay (only when not playing)
        stateOverlay
    }

    // MARK: - Snapshot Content

    private var snapshotContent: some View {
        Group {
            switch streamManager.state {
            case .idle:
                VStack(spacing: 8) {
                    Image(systemName: "video.slash")
                        .font(.title2)
                        .foregroundColor(.gray)
                    Text("No Stream")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

            case .connecting:
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Connecting...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }

            case .playing:
                if let frame = streamManager.currentFrame {
                    Image(nsImage: frame)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else {
                    ProgressView()
                }

            case .error(let message):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.caption2)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .padding(4)
            }
        }
    }

    // MARK: - State Overlay (for MPV)

    @ViewBuilder
    private var stateOverlay: some View {
        switch streamManager.state {
        case .connecting:
            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Connecting...")
                    .font(.caption)
                    .foregroundColor(.white)
            }
        case .error(let message):
            VStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text(message)
                    .font(.caption2)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
        default:
            EmptyView()
        }
    }

    // MARK: - Camera Name Overlay

    private var cameraNameOverlay: some View {
        VStack {
            HStack {
                Text(cameraName)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(4)
                Spacer()

                // Indicator: MPV or Snapshot mode
                if !useMPV {
                    Image(systemName: "photo")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                        .padding(2)
                        .background(Color.black.opacity(0.6))
                        .cornerRadius(4)
                        .help("Snapshot mode (RTSP unavailable)")
                }
            }
            Spacer()
        }
        .padding(4)
    }

    // MARK: - Fallback

    private func startSnapshotFallback() {
        streamManager.startSnapshotStream(
            apiClient: apiClient,
            baseURL: baseURL,
            cameraId: cameraId,
            interval: 1.0
        )
    }
}
