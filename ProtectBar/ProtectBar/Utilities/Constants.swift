import Foundation

enum AppConstants {
    static let appName = "ProtectBar"
    static let defaultRTSPPort = 7447
    static let defaultRTSPSPort = 7441
    static let snapshotWidth = 640
    static let snapshotHeight = 360

    enum API {
        static let loginPath = "/api/auth/login"
        static let bootstrapPath = "/proxy/protect/api/bootstrap"
        static let camerasPath = "/proxy/protect/api/cameras"

        static func snapshotPath(cameraId: String, width: Int = snapshotWidth, height: Int = snapshotHeight) -> String {
            "/proxy/protect/api/cameras/\(cameraId)/snapshot?w=\(width)&h=\(height)"
        }

        static func rtspURL(host: String, port: Int = defaultRTSPPort, rtspAlias: String) -> String {
            "rtsp://\(host):\(port)/\(rtspAlias)"
        }
    }

    enum Keychain {
        static let service = "com.protectbar.credentials"
        static let usernameKey = "protect_username"
        static let passwordKey = "protect_password"
    }

    enum UserDefaults {
        static let hostAddress = "host_address"
        static let connectionType = "connection_type"
        static let isConfigured = "is_configured"
        static let gridColumns = "grid_columns"
        static let streamQuality = "stream_quality"
        static let refreshInterval = "refresh_interval"
        static let hiddenCameraIds = "hidden_camera_ids"
    }
}
