import SwiftUI
import AppKit

/// Manages pinned camera windows (always-on-top widgets)
@MainActor
final class WindowManager: ObservableObject {

    struct PinnedWindow: Identifiable {
        let id: String // camera ID
        let window: NSWindow
        let cameraName: String
    }

    @Published var pinnedWindows: [PinnedWindow] = []

    // MARK: - Pin Camera

    func pinCamera(
        camera: Camera,
        rtspURL: String?,
        apiClient: ProtectAPIClient,
        baseURL: String
    ) {
        // Check if already pinned
        if let existing = pinnedWindows.first(where: { $0.id == camera.id }) {
            existing.window.makeKeyAndOrderFront(nil)
            return
        }

        let streamManager = RTSPStreamManager()

        let contentView = PinnedCameraContentView(
            camera: camera,
            rtspURL: rtspURL,
            streamManager: streamManager,
            apiClient: apiClient,
            baseURL: baseURL,
            onClose: { [weak self] in
                self?.unpinCamera(cameraId: camera.id)
            }
        )

        let hostingView = NSHostingView(rootView: contentView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 200),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.contentView = hostingView
        window.title = camera.name
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.level = .floating // Always on top
        window.collectionBehavior = [.canJoinAllSpaces, .stationary]
        window.backgroundColor = .black
        window.minSize = NSSize(width: 200, height: 130)
        window.isReleasedWhenClosed = false

        // Position in top-right corner
        if let screen = NSScreen.main {
            let screenFrame = screen.visibleFrame
            let windowFrame = window.frame
            let x = screenFrame.maxX - windowFrame.width - 20
            let y = screenFrame.maxY - windowFrame.height - 20 - CGFloat(pinnedWindows.count * 220)
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.makeKeyAndOrderFront(nil)

        let pinned = PinnedWindow(id: camera.id, window: window, cameraName: camera.name)
        pinnedWindows.append(pinned)
    }

    // MARK: - Unpin Camera

    func unpinCamera(cameraId: String) {
        if let index = pinnedWindows.firstIndex(where: { $0.id == cameraId }) {
            pinnedWindows[index].window.close()
            pinnedWindows.remove(at: index)
        }
    }

    // MARK: - Unpin All

    func unpinAll() {
        for pinned in pinnedWindows {
            pinned.window.close()
        }
        pinnedWindows.removeAll()
    }

    func isPinned(cameraId: String) -> Bool {
        pinnedWindows.contains { $0.id == cameraId }
    }
}

// MARK: - Pinned Camera Content View

struct PinnedCameraContentView: View {
    let camera: Camera
    let rtspURL: String?
    @ObservedObject var streamManager: RTSPStreamManager
    let apiClient: ProtectAPIClient
    let baseURL: String
    let onClose: () -> Void

    @State private var isHovering = false

    var body: some View {
        ZStack {
            VLCPlayerView(
                rtspURL: rtspURL,
                cameraName: camera.name,
                streamManager: streamManager,
                apiClient: apiClient,
                baseURL: baseURL,
                cameraId: camera.id
            )

            // Close button on hover
            if isHovering {
                VStack {
                    HStack {
                        Spacer()
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title3)
                                .foregroundColor(.white)
                                .shadow(radius: 2)
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                    }
                    Spacer()
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}
