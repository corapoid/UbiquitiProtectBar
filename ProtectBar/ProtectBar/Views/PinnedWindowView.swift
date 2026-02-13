import SwiftUI

/// Expanded single camera view (shown when clicking a camera in the grid)
struct PinnedWindowView: View {
    let camera: Camera
    let rtspURL: String?
    let apiClient: ProtectAPIClient
    let baseURL: String
    let onClose: () -> Void
    let onPin: () -> Void

    @StateObject private var streamManager = RTSPStreamManager()

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.plain)

                Spacer()

                Text(camera.name)
                    .font(.subheadline)
                    .fontWeight(.medium)

                Spacer()

                Button(action: onPin) {
                    Image(systemName: "pin.fill")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Pin as floating widget")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            // Stream view
            VLCPlayerView(
                rtspURL: rtspURL,
                cameraName: camera.name,
                streamManager: streamManager,
                apiClient: apiClient,
                baseURL: baseURL,
                cameraId: camera.id
            )

            // Info bar
            HStack {
                if let channel = camera.bestAvailableChannel {
                    Text(channel.resolution)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text("\(channel.fps) fps")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
                Circle()
                    .fill(camera.isConnected ? Color.green : Color.red)
                    .frame(width: 6, height: 6)
                Text(camera.isConnected ? "Connected" : "Offline")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
    }
}
