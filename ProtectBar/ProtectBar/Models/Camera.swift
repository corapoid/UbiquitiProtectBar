import Foundation

// MARK: - Camera Channel

struct CameraChannel: Codable, Identifiable, Sendable {
    let id: Int
    let name: String
    let enabled: Bool
    let isRtspEnabled: Bool
    let rtspAlias: String?
    let width: Int
    let height: Int
    let fps: Int
    let bitrate: Int
    let idrInterval: Int?

    var resolution: String {
        "\(width)x\(height)"
    }
}

// MARK: - Camera Feature Flags

struct CameraFeatureFlags: Codable, Sendable {
    let isDoorbell: Bool?
    let hasSmartDetect: Bool?
    let hasLedStatus: Bool?
    let hasMotionZones: Bool?
}

// MARK: - Camera

struct Camera: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let type: String
    let mac: String?
    let host: String?
    let isConnected: Bool
    let isRecording: Bool?
    let state: String
    let channels: [CameraChannel]
    let featureFlags: CameraFeatureFlags?
    let lastMotion: Int?
    let isMotionDetected: Bool?
    let marketName: String?
    
    static func == (lhs: Camera, rhs: Camera) -> Bool {
        lhs.id == rhs.id
    }

    /// Low quality channel (smallest resolution) for grid view
    var lowQualityChannel: CameraChannel? {
        channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .min { $0.width < $1.width }
    }

    /// High quality channel (largest resolution) for full view
    var highQualityChannel: CameraChannel? {
        channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .max { $0.width < $1.width }
    }

    /// Medium quality channel, or fallback to low
    var mediumQualityChannel: CameraChannel? {
        let rtspChannels = channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .sorted { $0.width < $1.width }
        guard rtspChannels.count > 1 else { return rtspChannels.first }
        return rtspChannels[rtspChannels.count / 2]
    }

    /// Any available RTSP channel (tries medium → low → high)
    var bestAvailableChannel: CameraChannel? {
        mediumQualityChannel ?? lowQualityChannel ?? highQualityChannel
    }

    /// Whether any RTSP channel is available
    var hasRTSP: Bool {
        channels.contains { $0.isRtspEnabled && $0.rtspAlias != nil }
    }
}
