import Foundation
import SwiftUI

// MARK: - Connection Type

enum ConnectionType: String, Codable, CaseIterable, Sendable {
    case local

    var displayName: String {
        switch self {
        case .local: return "Local Network"
        }
    }

    var description: String {
        switch self {
        case .local: return "Connect directly to your UniFi Protect NVR on your local network"
        }
    }
}

// MARK: - Stream Quality

enum StreamQuality: String, Codable, CaseIterable, Sendable {
    case low
    case medium
    case high

    var displayName: String {
        switch self {
        case .low: return "Low (360p)"
        case .medium: return "Medium (720p)"
        case .high: return "High (1080p+)"
        }
    }
}

// MARK: - App Settings

@MainActor
final class AppSettings: ObservableObject {
    @AppStorage(AppConstants.UserDefaults.hostAddress) var hostAddress: String = ""
    @AppStorage(AppConstants.UserDefaults.connectionType) var connectionTypeRaw: String = ConnectionType.local.rawValue
    @AppStorage(AppConstants.UserDefaults.isConfigured) var isConfigured: Bool = false
    @AppStorage(AppConstants.UserDefaults.gridColumns) var gridColumns: Int = 2
    @AppStorage(AppConstants.UserDefaults.streamQuality) var streamQualityRaw: String = StreamQuality.low.rawValue
    @AppStorage(AppConstants.UserDefaults.useAPIKey) var useAPIKey: Bool = true
    @AppStorage(AppConstants.UserDefaults.hiddenCameraIds) var hiddenCameraIdsData: Data = Data()
    
    var hiddenCameraIds: Set<String> {
        get {
            (try? JSONDecoder().decode(Set<String>.self, from: hiddenCameraIdsData)) ?? []
        }
        set {
            hiddenCameraIdsData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }
    
    func toggleCameraHidden(_ cameraId: String) {
        var hidden = hiddenCameraIds
        if hidden.contains(cameraId) {
            hidden.remove(cameraId)
        } else {
            hidden.insert(cameraId)
        }
        hiddenCameraIds = hidden
    }
    
    func isCameraHidden(_ cameraId: String) -> Bool {
        hiddenCameraIds.contains(cameraId)
    }

    var connectionType: ConnectionType {
        get { ConnectionType(rawValue: connectionTypeRaw) ?? .local }
        set { connectionTypeRaw = newValue.rawValue }
    }

    var streamQuality: StreamQuality {
        get { StreamQuality(rawValue: streamQualityRaw) ?? .low }
        set { streamQualityRaw = newValue.rawValue }
    }

    /// Normalized host (strip protocol if user added it)
    var normalizedHost: String {
        var host = hostAddress
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if host.hasPrefix("https://") {
            host = String(host.dropFirst(8))
        } else if host.hasPrefix("http://") {
            host = String(host.dropFirst(7))
        }
        if host.hasSuffix("/") {
            host = String(host.dropLast())
        }
        return host
    }

    var baseURL: String {
        "https://\(normalizedHost)"
    }
}
