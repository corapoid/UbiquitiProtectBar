import Foundation

// MARK: - NVR Ports

struct NVRPorts: Codable, Sendable {
    let rtsp: Int?
    let rtsps: Int?
    let rtmp: Int?
    let http: Int?
    let https: Int?
    let discoveryClient: Int?
}

// MARK: - NVR Info

struct NVRInfo: Codable, Sendable {
    let id: String?
    let name: String?
    let host: String?
    let mac: String?
    let firmwareVersion: String?
    let version: String?
    let isSetup: Bool?
    let ports: NVRPorts?
    let lastUpdateId: String?

    var rtspPort: Int {
        ports?.rtsp ?? AppConstants.defaultRTSPPort
    }
}

// MARK: - Bootstrap Response

struct BootstrapResponse: Codable, Sendable {
    let cameras: [Camera]
    let nvr: NVRInfo
    let lastUpdateId: String?
}
