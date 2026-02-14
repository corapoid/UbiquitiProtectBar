import XCTest

// MARK: - Test Doubles (mirror of main app types)

enum TestConnectionType: String, CaseIterable {
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

enum TestStreamQuality: String, CaseIterable {
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

// MARK: - Tests

final class AppSettingsTests: XCTestCase {
    
    // MARK: - ConnectionType Tests
    
    func testConnectionTypeRawValue() {
        XCTAssertEqual(TestConnectionType.local.rawValue, "local")
    }
    
    func testConnectionTypeDisplayName() {
        XCTAssertEqual(TestConnectionType.local.displayName, "Local Network")
    }
    
    func testConnectionTypeDescription() {
        XCTAssertTrue(TestConnectionType.local.description.contains("local network"))
    }
    
    // MARK: - StreamQuality Tests
    
    func testStreamQualityRawValues() {
        XCTAssertEqual(TestStreamQuality.low.rawValue, "low")
        XCTAssertEqual(TestStreamQuality.medium.rawValue, "medium")
        XCTAssertEqual(TestStreamQuality.high.rawValue, "high")
    }
    
    func testStreamQualityDisplayNames() {
        XCTAssertEqual(TestStreamQuality.low.displayName, "Low (360p)")
        XCTAssertEqual(TestStreamQuality.medium.displayName, "Medium (720p)")
        XCTAssertEqual(TestStreamQuality.high.displayName, "High (1080p+)")
    }
    
    func testStreamQualityAllCases() {
        XCTAssertEqual(TestStreamQuality.allCases.count, 3)
        XCTAssertTrue(TestStreamQuality.allCases.contains(.low))
        XCTAssertTrue(TestStreamQuality.allCases.contains(.medium))
        XCTAssertTrue(TestStreamQuality.allCases.contains(.high))
    }
    
    // MARK: - Host Normalization Tests
    
    func testHostNormalization() {
        let testCases = [
            ("192.168.1.1", "192.168.1.1"),
            ("https://192.168.1.1", "192.168.1.1"),
            ("http://192.168.1.1", "192.168.1.1"),
            ("192.168.1.1/", "192.168.1.1"),
            ("https://192.168.1.1/", "192.168.1.1"),
            ("  192.168.1.1  ", "192.168.1.1"),
            ("nvr.local", "nvr.local"),
            ("https://nvr.local/", "nvr.local")
        ]
        
        for (input, expected) in testCases {
            let normalized = normalizeHost(input)
            XCTAssertEqual(normalized, expected, "Failed for input: \(input)")
        }
    }
    
    // MARK: - Helper
    
    private func normalizeHost(_ input: String) -> String {
        var host = input.trimmingCharacters(in: .whitespacesAndNewlines)
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
}
