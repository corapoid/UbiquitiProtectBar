import Foundation

// MARK: - Smart Detection Types

enum SmartDetectType: String, Codable, CaseIterable, Sendable {
    case person
    case vehicle
    case animal
    case package
    case licensePlate
    case face
    
    var displayName: String {
        switch self {
        case .person: return "Person"
        case .vehicle: return "Vehicle"
        case .animal: return "Animal"
        case .package: return "Package"
        case .licensePlate: return "License Plate"
        case .face: return "Face"
        }
    }
    
    var iconName: String {
        switch self {
        case .person: return "person.fill"
        case .vehicle: return "car.fill"
        case .animal: return "pawprint.fill"
        case .package: return "shippingbox.fill"
        case .licensePlate: return "rectangle.fill"
        case .face: return "face.smiling"
        }
    }
}

// MARK: - Smart Detection Event

struct SmartDetectEvent: Codable, Identifiable, Sendable {
    let id: String
    let type: String  // Raw type from API
    let score: Int?
    let start: Int?  // Unix timestamp ms
    let end: Int?
    
    var smartType: SmartDetectType? {
        SmartDetectType(rawValue: type)
    }
    
    var startDate: Date? {
        guard let start else { return nil }
        return Date(timeIntervalSince1970: Double(start) / 1000)
    }
}

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
    let hasChime: Bool?
    let hasSpeaker: Bool?
    let hasLcdScreen: Bool?
    let smartDetectTypes: [String]?
    
    var supportedSmartTypes: [SmartDetectType] {
        (smartDetectTypes ?? []).compactMap { SmartDetectType(rawValue: $0) }
    }
}

// MARK: - LCD Message (Doorbell)

struct LCDMessage: Codable, Sendable {
    let type: String?
    let text: String?
    let resetAt: Int?
    
    enum MessageType: String {
        case customMessage = "CUSTOM_MESSAGE"
        case leavePackageAtDoor = "LEAVE_PACKAGE_AT_DOOR"
        case doNotDisturb = "DO_NOT_DISTURB"
    }
    
    var messageType: MessageType? {
        guard let type else { return nil }
        return MessageType(rawValue: type)
    }
}

// MARK: - Motion Event

struct MotionEvent: Codable, Identifiable, Sendable {
    let id: String
    let start: Int
    let end: Int?
    let camera: String  // Camera ID
    let score: Int?
    let smartDetectTypes: [String]?
    let thumbnail: String?  // Thumbnail ID
    
    var startDate: Date {
        Date(timeIntervalSince1970: Double(start) / 1000)
    }
    
    var endDate: Date? {
        guard let end else { return nil }
        return Date(timeIntervalSince1970: Double(end) / 1000)
    }
    
    var duration: TimeInterval? {
        guard let end else { return nil }
        return Double(end - start) / 1000
    }
    
    var smartTypes: [SmartDetectType] {
        (smartDetectTypes ?? []).compactMap { SmartDetectType(rawValue: $0) }
    }
    
    var hasSmartDetection: Bool {
        !smartTypes.isEmpty
    }
}

// MARK: - Ring Event (Doorbell)

struct RingEvent: Codable, Identifiable, Sendable {
    let id: String
    let start: Int
    let end: Int?
    let camera: String  // Camera ID
    
    var startDate: Date {
        Date(timeIntervalSince1970: Double(start) / 1000)
    }
}

// MARK: - Camera

struct Camera: Codable, Identifiable, Sendable, Equatable, Hashable {
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
    // Smart detection
    let lastSmartDetect: Int?
    let lastSmartDetectTypes: [String]?
    // Doorbell specific
    let lastRing: Int?
    let lcdMessage: LCDMessage?
    
    static func == (lhs: Camera, rhs: Camera) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    // MARK: - Computed Properties
    
    var isDoorbell: Bool {
        featureFlags?.isDoorbell == true
    }
    
    var hasSmartDetect: Bool {
        featureFlags?.hasSmartDetect == true
    }
    
    var supportedSmartTypes: [SmartDetectType] {
        featureFlags?.supportedSmartTypes ?? []
    }
    
    var lastSmartDetectDate: Date? {
        guard let ts = lastSmartDetect else { return nil }
        return Date(timeIntervalSince1970: Double(ts) / 1000)
    }
    
    var lastRingDate: Date? {
        guard let ts = lastRing else { return nil }
        return Date(timeIntervalSince1970: Double(ts) / 1000)
    }
    
    var recentSmartDetectTypes: [SmartDetectType] {
        (lastSmartDetectTypes ?? []).compactMap { SmartDetectType(rawValue: $0) }
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
