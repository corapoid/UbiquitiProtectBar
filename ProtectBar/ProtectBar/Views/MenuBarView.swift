import SwiftUI
import os.log
import Sparkle

private let logger = Logger(subsystem: "com.protectbar.app", category: "MenuBar")

/// Main menu bar popover content
struct MenuBarView: View {

    @ObservedObject var settings: AppSettings
    @ObservedObject var connectionVM: ConnectionViewModel
    @ObservedObject var gridVM: CameraGridViewModel
    @ObservedObject var windowManager: WindowManager
    let apiClient: ProtectAPIClient
    let updater: SPUUpdater
    let isMenuVisible: Bool

    @State private var showSettings = false
    @State private var showEvents = false
    @State private var currentTab: Tab = .cameras
    @State private var eventPlaybackTime: Date?
    @State private var eventPlaybackCamera: Camera?

    enum Tab {
        case cameras
        case events
        case settings
        case expandedCamera
    }

    var body: some View {
        VStack(spacing: 0) {
            if !settings.isConfigured || showSettings {
                settingsContent
            } else if let camera = eventPlaybackCamera, let time = eventPlaybackTime {
                // Event playback mode
                CameraDetailView(
                    camera: camera,
                    rtspURL: gridVM.rtspURL(for: camera, settings: settings),
                    apiClient: apiClient,
                    baseURL: settings.baseURL,
                    onClose: {
                        eventPlaybackCamera = nil
                        eventPlaybackTime = nil
                    },
                    initialPlaybackTime: time
                )
            } else if showEvents {
                eventsContent
            } else if let camera = gridVM.selectedCamera {
                // Camera detail view with timeline
                CameraDetailView(
                    camera: camera,
                    rtspURL: gridVM.rtspURL(for: camera, settings: settings),
                    apiClient: apiClient,
                    baseURL: settings.baseURL,
                    onClose: { gridVM.clearSelection() }
                )
            } else {
                mainContent
            }

            Divider()
            footerBar
        }
        .frame(width: popoverWidth, height: popoverHeight)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            logger.error("[MenuBar] onAppear - isConfigured: \(settings.isConfigured), isConnected: \(connectionVM.isConnected)")
            if settings.isConfigured && !connectionVM.isConnected {
                logger.error("[MenuBar] Starting connection...")
                Task {
                    await connectionVM.connect(settings: settings)
                    // Load cameras after successful connection
                    if connectionVM.isConnected {
                        await gridVM.loadCameras(settings: settings)
                    }
                }
            }
        }
        .onChange(of: connectionVM.isConnected) { isConnected in
            // Load cameras when connection state changes to connected
            if isConnected {
                Task { await gridVM.loadCameras(settings: settings) }
            }
        }
    }

    // MARK: - Dimensions
    
    private let cellWidth: CGFloat = 220
    private let cellHeight: CGFloat = 124  // 16:9 ratio
    private let gridSpacing: CGFloat = 4
    private let headerHeight: CGFloat = 50
    
    private var visibleCameraCount: Int {
        gridVM.cameras.filter { !settings.isCameraHidden($0.id) }.count
    }
    
    private var effectiveColumns: Int {
        if settings.gridColumns == 0 {
            return max(visibleCameraCount, 1)
        }
        return settings.gridColumns
    }
    
    private var rowCount: Int {
        let cols = effectiveColumns
        return Int(ceil(Double(visibleCameraCount) / Double(cols)))
    }

    private var popoverWidth: CGFloat {
        if !settings.isConfigured || showSettings {
            return 400
        }
        let cols = CGFloat(effectiveColumns)
        return cols * cellWidth + (cols + 1) * gridSpacing + 8
    }

    private var popoverHeight: CGFloat {
        if !settings.isConfigured || showSettings {
            return 500
        }
        let rows = CGFloat(max(rowCount, 1))
        return rows * cellHeight + (rows + 1) * gridSpacing + headerHeight + 8
    }

    // MARK: - Main Content (Camera Grid)

    private var mainContent: some View {
        VStack(spacing: 0) {
            if connectionVM.isConnecting {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Connecting to NVR...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = connectionVM.errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await connectionVM.connect(settings: settings) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                CameraGridView(
                    viewModel: gridVM,
                    settings: settings,
                    apiClient: apiClient,
                    isMenuVisible: isMenuVisible,
                    onPinCamera: { camera in
                        pinCamera(camera)
                    }
                )
                .onAppear {
                    Task { await gridVM.loadCameras(settings: settings) }
                }
            }
        }
    }

    // MARK: - Settings Content

    private var settingsContent: some View {
        SettingsView(
            settings: settings,
            connectionVM: connectionVM,
            updater: updater,
            onDismiss: { showSettings = false }
        )
    }
    
    // MARK: - Events Content
    
    private var eventsContent: some View {
        VStack(spacing: 0) {
            // Back button header
            HStack {
                Button(
                    action: { showEvents = false },
                    label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Back")
                        }
                        .font(.caption)
                    }
                )
                .buttonStyle(.plain)
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            
            Divider()
            
            EventsView(
                settings: settings,
                apiClient: apiClient,
                cameras: gridVM.cameras,
                onPlayEvent: { camera, time in
                    eventPlaybackCamera = camera
                    eventPlaybackTime = time
                    showEvents = false
                }
            )
        }
    }

    // MARK: - Footer

    private var footerBar: some View {
        HStack {
            // Settings button
            Button(action: { showSettings.toggle() }, label: {
                Image(systemName: "gear")
                    .font(.caption)
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
            .help("Settings")
            
            // Events button
            if settings.isConfigured && connectionVM.isConnected {
                Button(action: { showEvents.toggle() }, label: {
                    Image(systemName: "bell")
                        .font(.caption)
                        .foregroundColor(showEvents ? .accentColor : .secondary)
                })
                .buttonStyle(.plain)
                .help("Recent Events")
            }

            if connectionVM.isConnected {
                Circle()
                    .fill(Color.green)
                    .frame(width: 6, height: 6)
                Text("\(gridVM.cameras.count) cameras")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if !windowManager.pinnedWindows.isEmpty {
                Button("Unpin All (\(windowManager.pinnedWindows.count))") {
                    windowManager.unpinAll()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.secondary)
            }

            // Quit button
            Button(action: { NSApplication.shared.terminate(nil) }, label: {
                Image(systemName: "power")
                    .font(.caption)
                    .foregroundColor(.secondary)
            })
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Pin

    private func pinCamera(_ camera: Camera) {
        windowManager.pinCamera(
            camera: camera,
            rtspURL: gridVM.rtspURL(for: camera, settings: settings),
            apiClient: apiClient,
            baseURL: settings.baseURL
        )
    }
}
