import XCTest

// MARK: - Test Double (mirror of main app Constants)

enum TestAppConstants {
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
}

// MARK: - Tests

final class ConstantsTests: XCTestCase {
    
    // MARK: - API Path Tests
    
    func testLoginPath() {
        XCTAssertEqual(TestAppConstants.API.loginPath, "/api/auth/login")
    }
    
    func testBootstrapPath() {
        XCTAssertEqual(TestAppConstants.API.bootstrapPath, "/proxy/protect/api/bootstrap")
    }
    
    func testSnapshotPath() {
        let path = TestAppConstants.API.snapshotPath(cameraId: "camera123")
        XCTAssertEqual(path, "/proxy/protect/api/cameras/camera123/snapshot?w=640&h=360")
    }
    
    func testSnapshotPathWithCustomSize() {
        let path = TestAppConstants.API.snapshotPath(cameraId: "camera123", width: 1280, height: 720)
        XCTAssertEqual(path, "/proxy/protect/api/cameras/camera123/snapshot?w=1280&h=720")
    }
    
    func testRtspURL() {
        let url = TestAppConstants.API.rtspURL(host: "192.168.1.1", rtspAlias: "camera_high")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7447/camera_high")
    }
    
    func testRtspURLWithCustomPort() {
        let url = TestAppConstants.API.rtspURL(host: "192.168.1.1", port: 7441, rtspAlias: "camera_high")
        XCTAssertEqual(url, "rtsp://192.168.1.1:7441/camera_high")
    }
    
    func testRtspURLWithHostname() {
        let url = TestAppConstants.API.rtspURL(host: "nvr.local", rtspAlias: "camera_high")
        XCTAssertEqual(url, "rtsp://nvr.local:7447/camera_high")
    }
    
    func testSnapshotPathWithSpecialCharacters() {
        let path = TestAppConstants.API.snapshotPath(cameraId: "camera-123-abc")
        XCTAssertTrue(path.contains("camera-123-abc"))
    }
    
    // MARK: - Default Values Tests
    
    func testDefaultRTSPPort() {
        XCTAssertEqual(TestAppConstants.defaultRTSPPort, 7447)
    }
    
    func testDefaultRTSPSPort() {
        XCTAssertEqual(TestAppConstants.defaultRTSPSPort, 7441)
    }
    
    func testSnapshotDimensions() {
        XCTAssertEqual(TestAppConstants.snapshotWidth, 640)
        XCTAssertEqual(TestAppConstants.snapshotHeight, 360)
    }
    
    func testAppName() {
        XCTAssertEqual(TestAppConstants.appName, "ProtectBar")
    }
}
