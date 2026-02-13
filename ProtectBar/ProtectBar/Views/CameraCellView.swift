import SwiftUI

/// Single camera cell in the grid — shows live RTSP/snapshot stream
struct CameraCellView: View {
    let camera: Camera
    let rtspURL: String?
    let apiClient: ProtectAPIClient
    let baseURL: String
    let isVisible: Bool
    let onTap: () -> Void
    let onPin: () -> Void
    var isMotionDetected: Bool = false

    @StateObject private var streamManager = RTSPStreamManager()
    @State private var isHovering = false

    var body: some View {
        ZStack {
            VLCPlayerView(
                rtspURL: rtspURL,
                cameraName: camera.name,
                streamManager: streamManager,
                apiClient: apiClient,
                baseURL: baseURL,
                cameraId: camera.id,
                isVisible: isVisible
            )

            // Motion detection indicator
            if isMotionDetected {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 2)
                    .animation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true), value: isMotionDetected)
            }

            // Hover overlay with controls
            if isHovering {
                Color.black.opacity(0.3)
                    .cornerRadius(6)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        // Pin button
                        Button(action: onPin) {
                            Image(systemName: "pin.fill")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Pin as widget")

                        // Expand button
                        Button(action: onTap) {
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .font(.caption)
                                .foregroundColor(.white)
                                .padding(6)
                                .background(Color.black.opacity(0.6))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Expand camera")
                    }
                    .padding(8)
                }
            }

            // Status indicators
            VStack {
                HStack {
                    // Doorbell indicator
                    if camera.isDoorbell {
                        Image(systemName: "bell.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.yellow)
                            .padding(4)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(4)
                    }
                    
                    // Last smart detection time (not motion)
                    if let lastDetect = camera.lastSmartDetectDate {
                        Text(formatTimeAgo(lastDetect))
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.8))
                            .cornerRadius(4)
                    }

                    Spacer()

                    // Connection status
                    Circle()
                        .fill(camera.isConnected ? Color.green : Color.red)
                        .frame(width: 6, height: 6)
                        .padding(6)
                }
                Spacer()
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .cornerRadius(8)
        .shadow(color: .black.opacity(0.2), radius: 2, x: 0, y: 1)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onTapGesture {
            onTap()
        }
    }
    
    private func formatTimeAgo(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 {
            return "\(Int(interval))s"
        } else if interval < 3600 {
            return "\(Int(interval / 60))m"
        } else if interval < 86400 {
            return "\(Int(interval / 3600))h"
        } else {
            return "\(Int(interval / 86400))d"
        }
    }
}
