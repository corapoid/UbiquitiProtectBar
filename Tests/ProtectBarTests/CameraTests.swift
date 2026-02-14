import XCTest

// MARK: - Test Doubles (mirror of main app types)

struct TestCameraChannel: Codable {
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

struct TestCamera: Codable {
    let id: String
    let name: String
    let type: String
    let mac: String?
    let host: String?
    let isConnected: Bool
    let isRecording: Bool?
    let state: String
    let channels: [TestCameraChannel]

    var lowQualityChannel: TestCameraChannel? {
        channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .min { $0.width < $1.width }
    }

    var highQualityChannel: TestCameraChannel? {
        channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .max { $0.width < $1.width }
    }

    var mediumQualityChannel: TestCameraChannel? {
        let rtspChannels = channels
            .filter { $0.isRtspEnabled && $0.rtspAlias != nil }
            .sorted { $0.width < $1.width }
        guard rtspChannels.count > 1 else { return rtspChannels.first }
        return rtspChannels[rtspChannels.count / 2]
    }

    var hasRTSP: Bool {
        channels.contains { $0.isRtspEnabled && $0.rtspAlias != nil }
    }
}

// MARK: - Tests

final class CameraTests: XCTestCase {
    
    // MARK: - Channel Tests
    
    func testChannelResolution() {
        let channel = createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true)
        XCTAssertEqual(channel.resolution, "1920x1080")
    }
    
    // MARK: - Camera Channel Selection Tests
    
    func testLowQualityChannelSelection() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true),
            createChannel(id: 1, width: 1280, height: 720, rtspEnabled: true),
            createChannel(id: 2, width: 640, height: 360, rtspEnabled: true)
        ])
        
        let lowChannel = camera.lowQualityChannel
        XCTAssertNotNil(lowChannel)
        XCTAssertEqual(lowChannel?.width, 640)
    }
    
    func testHighQualityChannelSelection() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true),
            createChannel(id: 1, width: 1280, height: 720, rtspEnabled: true),
            createChannel(id: 2, width: 640, height: 360, rtspEnabled: true)
        ])
        
        let highChannel = camera.highQualityChannel
        XCTAssertNotNil(highChannel)
        XCTAssertEqual(highChannel?.width, 1920)
    }
    
    func testMediumQualityChannelSelection() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true),
            createChannel(id: 1, width: 1280, height: 720, rtspEnabled: true),
            createChannel(id: 2, width: 640, height: 360, rtspEnabled: true)
        ])
        
        let mediumChannel = camera.mediumQualityChannel
        XCTAssertNotNil(mediumChannel)
        XCTAssertEqual(mediumChannel?.width, 1280)
    }
    
    func testChannelSelectionWithDisabledRTSP() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: false),
            createChannel(id: 1, width: 1280, height: 720, rtspEnabled: true),
            createChannel(id: 2, width: 640, height: 360, rtspEnabled: false)
        ])
        
        XCTAssertEqual(camera.lowQualityChannel?.width, 1280)
        XCTAssertEqual(camera.highQualityChannel?.width, 1280)
    }
    
    func testChannelSelectionWithNoRTSP() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: false),
            createChannel(id: 1, width: 1280, height: 720, rtspEnabled: false)
        ])
        
        XCTAssertNil(camera.lowQualityChannel)
        XCTAssertNil(camera.highQualityChannel)
        XCTAssertFalse(camera.hasRTSP)
    }
    
    func testHasRTSP() {
        let cameraWithRTSP = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true)
        ])
        
        let cameraWithoutRTSP = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: false)
        ])
        
        XCTAssertTrue(cameraWithRTSP.hasRTSP)
        XCTAssertFalse(cameraWithoutRTSP.hasRTSP)
    }
    
    // MARK: - JSON Decoding Tests
    
    func testCameraDecoding() throws {
        let json = """
        {
            "id": "test-camera-id",
            "name": "Front Door",
            "type": "UVC-G4-PRO",
            "mac": "00:11:22:33:44:55",
            "host": "192.168.1.100",
            "isConnected": true,
            "isRecording": true,
            "state": "CONNECTED",
            "channels": [
                {
                    "id": 0,
                    "name": "High",
                    "enabled": true,
                    "isRtspEnabled": true,
                    "rtspAlias": "front_door_high",
                    "width": 1920,
                    "height": 1080,
                    "fps": 30,
                    "bitrate": 4000,
                    "idrInterval": 5
                }
            ]
        }
        """
        
        let data = json.data(using: .utf8)!
        let camera = try JSONDecoder().decode(TestCamera.self, from: data)
        
        XCTAssertEqual(camera.id, "test-camera-id")
        XCTAssertEqual(camera.name, "Front Door")
        XCTAssertEqual(camera.type, "UVC-G4-PRO")
        XCTAssertTrue(camera.isConnected)
        XCTAssertEqual(camera.channels.count, 1)
        XCTAssertEqual(camera.channels.first?.rtspAlias, "front_door_high")
    }
    
    func testSingleChannelMediumFallback() {
        let camera = createTestCamera(withChannels: [
            createChannel(id: 0, width: 1920, height: 1080, rtspEnabled: true)
        ])
        
        // With single channel, medium should fallback to that channel
        XCTAssertEqual(camera.mediumQualityChannel?.width, 1920)
    }
    
    // MARK: - Helpers
    
    private func createChannel(
        id: Int,
        width: Int,
        height: Int,
        rtspEnabled: Bool,
        alias: String? = "test_alias"
    ) -> TestCameraChannel {
        TestCameraChannel(
            id: id,
            name: "Channel \(id)",
            enabled: true,
            isRtspEnabled: rtspEnabled,
            rtspAlias: rtspEnabled ? alias : nil,
            width: width,
            height: height,
            fps: 30,
            bitrate: 2000,
            idrInterval: 5
        )
    }
    
    private func createTestCamera(withChannels channels: [TestCameraChannel]) -> TestCamera {
        TestCamera(
            id: "test-camera",
            name: "Test Camera",
            type: "UVC-G4-PRO",
            mac: "00:11:22:33:44:55",
            host: "192.168.1.100",
            isConnected: true,
            isRecording: true,
            state: "CONNECTED",
            channels: channels
        )
    }
}
