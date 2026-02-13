import Foundation

/// Localization helper for accessing localized strings
enum L10n {
    // MARK: - General
    static let appName = NSLocalizedString("app.name", comment: "App name")
    
    // MARK: - Connection
    enum Connection {
        static let local = NSLocalizedString("connection.local", comment: "Local network connection type")
        static let localDescription = NSLocalizedString("connection.local.description", comment: "Local network description")
    }
    
    // MARK: - Settings
    enum Settings {
        static let title = NSLocalizedString("settings.title", comment: "Settings title")
        static let connectionType = NSLocalizedString("settings.connection_type", comment: "Connection type label")
        static let nvrAddress = NSLocalizedString("settings.nvr_address", comment: "NVR address label")
        static let nvrAddressPlaceholder = NSLocalizedString("settings.nvr_address.placeholder", comment: "NVR address placeholder")
        static let authentication = NSLocalizedString("settings.authentication", comment: "Authentication label")
        static let apiKey = NSLocalizedString("settings.api_key", comment: "API key label")
        static let apiKeyHint = NSLocalizedString("settings.api_key.hint", comment: "API key hint")
        static let username = NSLocalizedString("settings.username", comment: "Username label")
        static let password = NSLocalizedString("settings.password", comment: "Password label")
        static let streamQuality = NSLocalizedString("settings.stream_quality", comment: "Stream quality label")
        static let streamQualityHint = NSLocalizedString("settings.stream_quality.hint", comment: "Stream quality hint")
        static let testConnection = NSLocalizedString("settings.test_connection", comment: "Test connection button")
        static let saveConnect = NSLocalizedString("settings.save_connect", comment: "Save & connect button")
        static let disconnectClear = NSLocalizedString("settings.disconnect_clear", comment: "Disconnect & clear button")
    }
    
    // MARK: - Quality
    enum Quality {
        static let low = NSLocalizedString("quality.low", comment: "Low quality")
        static let medium = NSLocalizedString("quality.medium", comment: "Medium quality")
        static let high = NSLocalizedString("quality.high", comment: "High quality")
    }
    
    // MARK: - Grid
    enum Grid {
        static func camerasCount(_ count: Int) -> String {
            String(format: NSLocalizedString("grid.cameras_count", comment: "Cameras count"), count)
        }
        static let loading = NSLocalizedString("grid.loading", comment: "Loading cameras")
        static let empty = NSLocalizedString("grid.empty", comment: "No cameras available")
        static let emptyHint = NSLocalizedString("grid.empty.hint", comment: "Empty hint")
        static let refresh = NSLocalizedString("grid.refresh", comment: "Refresh button")
        static let unpinAll = NSLocalizedString("grid.unpin_all", comment: "Unpin all button")
    }
    
    // MARK: - Camera
    enum Camera {
        static let hide = NSLocalizedString("camera.hide", comment: "Hide camera")
        static let show = NSLocalizedString("camera.show", comment: "Show camera")
        static let pin = NSLocalizedString("camera.pin", comment: "Pin to desktop")
        static let showHidden = NSLocalizedString("camera.show_hidden", comment: "Show hidden cameras")
        static let hideHidden = NSLocalizedString("camera.hide_hidden", comment: "Hide hidden cameras")
    }
    
    // MARK: - Layout
    enum Layout {
        static let twoColumns = NSLocalizedString("layout.2_columns", comment: "2 columns")
        static let fourColumns = NSLocalizedString("layout.4_columns", comment: "4 columns")
        static let singleRow = NSLocalizedString("layout.single_row", comment: "Single row")
    }
    
    // MARK: - Errors
    enum Error {
        static let invalidURL = NSLocalizedString("error.invalid_url", comment: "Invalid URL error")
        static let invalidResponse = NSLocalizedString("error.invalid_response", comment: "Invalid response error")
        static let unauthorized = NSLocalizedString("error.unauthorized", comment: "Unauthorized error")
        static let forbidden = NSLocalizedString("error.forbidden", comment: "Forbidden error")
        static let rateLimited = NSLocalizedString("error.rate_limited", comment: "Rate limited error")
        
        static func http(_ code: Int) -> String {
            String(format: NSLocalizedString("error.http", comment: "HTTP error"), code)
        }
        
        static func decoding(_ detail: String) -> String {
            String(format: NSLocalizedString("error.decoding", comment: "Decoding error"), detail)
        }
        
        static func connectionFailed(_ detail: String) -> String {
            String(format: NSLocalizedString("error.connection_failed", comment: "Connection failed error"), detail)
        }
    }
    
    // MARK: - Error Help
    enum ErrorHelp {
        static let unauthorized = NSLocalizedString("error.help.unauthorized", comment: "Unauthorized help")
        static let forbidden = NSLocalizedString("error.help.forbidden", comment: "Forbidden help")
        static let connection = NSLocalizedString("error.help.connection", comment: "Connection help")
    }
    
    // MARK: - Status
    enum Status {
        static let connected = NSLocalizedString("status.connected", comment: "Connected status")
        static let connecting = NSLocalizedString("status.connecting", comment: "Connecting status")
        static let disconnected = NSLocalizedString("status.disconnected", comment: "Disconnected status")
        static let error = NSLocalizedString("status.error", comment: "Error status")
    }
    
    // MARK: - Test
    enum Test {
        static func success(_ count: Int) -> String {
            String(format: NSLocalizedString("test.success", comment: "Test success"), count)
        }
        static let failed = NSLocalizedString("test.failed", comment: "Test failed")
    }
    
    // MARK: - Menu
    enum Menu {
        static let settings = NSLocalizedString("menu.settings", comment: "Settings menu item")
        static let quit = NSLocalizedString("menu.quit", comment: "Quit menu item")
        static let checkForUpdates = NSLocalizedString("menu.check_updates", comment: "Check for updates")
    }
}
