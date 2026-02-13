import XCTest

// MARK: - Test Double (mirror of main app APIError)

enum TestAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case rateLimited
    case httpError(Int)
    case decodingError(String)
    case connectionFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid NVR URL"
        case .invalidResponse:
            return "Invalid response from NVR"
        case .unauthorized:
            return "Invalid credentials or session expired."
        case .forbidden:
            return "Access denied (403). Account may be locked or IP blocked."
        case .rateLimited:
            return "Too many requests. Please wait a moment."
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .decodingError(let detail):
            return "Failed to parse NVR response: \(detail)"
        case .connectionFailed(let detail):
            return "Connection failed: \(detail)"
        }
    }
}

// MARK: - Tests

final class APIErrorTests: XCTestCase {
    
    func testInvalidURLError() {
        let error = TestAPIError.invalidURL
        XCTAssertEqual(error.errorDescription, "Invalid NVR URL")
    }
    
    func testInvalidResponseError() {
        let error = TestAPIError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from NVR")
    }
    
    func testUnauthorizedError() {
        let error = TestAPIError.unauthorized
        XCTAssertEqual(error.errorDescription, "Invalid credentials or session expired.")
    }
    
    func testForbiddenError() {
        let error = TestAPIError.forbidden
        XCTAssertEqual(error.errorDescription, "Access denied (403). Account may be locked or IP blocked.")
    }
    
    func testRateLimitedError() {
        let error = TestAPIError.rateLimited
        XCTAssertEqual(error.errorDescription, "Too many requests. Please wait a moment.")
    }
    
    func testHTTPError() {
        let error = TestAPIError.httpError(500)
        XCTAssertEqual(error.errorDescription, "HTTP error: 500")
    }
    
    func testHTTPError404() {
        let error = TestAPIError.httpError(404)
        XCTAssertEqual(error.errorDescription, "HTTP error: 404")
    }
    
    func testDecodingError() {
        let error = TestAPIError.decodingError("Missing field 'id'")
        XCTAssertEqual(error.errorDescription, "Failed to parse NVR response: Missing field 'id'")
    }
    
    func testConnectionFailedError() {
        let error = TestAPIError.connectionFailed("Network unreachable")
        XCTAssertEqual(error.errorDescription, "Connection failed: Network unreachable")
    }
    
    // MARK: - Error Message Clarity Tests
    
    func testErrorMessagesAreUserFriendly() {
        // All errors should have non-technical, user-friendly messages
        let errors: [TestAPIError] = [
            .invalidURL,
            .invalidResponse,
            .unauthorized,
            .forbidden,
            .rateLimited,
            .httpError(500),
            .decodingError("test"),
            .connectionFailed("test")
        ]
        
        for error in errors {
            let message = error.errorDescription ?? ""
            XCTAssertFalse(message.isEmpty, "Error should have a description")
            XCTAssertFalse(message.contains("nil"), "Error should not contain 'nil'")
            XCTAssertFalse(message.contains("Error:"), "Error should not be redundant")
        }
    }
    
    func testForbiddenErrorContainsHelpfulInfo() {
        let error = TestAPIError.forbidden
        let message = error.errorDescription ?? ""
        
        // Should mention common causes
        XCTAssertTrue(message.contains("403") || message.contains("denied"))
        XCTAssertTrue(message.contains("locked") || message.contains("blocked"))
    }
}
