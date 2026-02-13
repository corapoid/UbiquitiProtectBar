import SwiftUI
import AppKit
import Sparkle

struct ProtectBarApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var apiClient = ProtectAPIClient()
    @StateObject private var windowManager = WindowManager()
    @StateObject private var connectionVM: ConnectionViewModel
    @StateObject private var gridVM: CameraGridViewModel
    
    // Sparkle updater
    private let updaterController: SPUStandardUpdaterController

    init() {
        let api = ProtectAPIClient()
        _apiClient = StateObject(wrappedValue: api)
        _connectionVM = StateObject(wrappedValue: ConnectionViewModel(apiClient: api))
        _gridVM = StateObject(wrappedValue: CameraGridViewModel(apiClient: api))
        _settings = StateObject(wrappedValue: AppSettings())
        _windowManager = StateObject(wrappedValue: WindowManager())
        
        // Initialize Sparkle updater
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                settings: settings,
                connectionVM: connectionVM,
                gridVM: gridVM,
                windowManager: windowManager,
                apiClient: apiClient,
                updater: updaterController.updater
            )
        } label: {
            Label("ProtectBar", systemImage: "video.fill")
        }
        .menuBarExtraStyle(.window)
    }
}
