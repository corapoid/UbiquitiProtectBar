import Foundation
import os.log

private let logger = Logger(subsystem: "com.protectbar.app", category: "API")

/// Authentication method for UniFi Protect
enum AuthMethod: String, CaseIterable, Identifiable {
    case apiKey = "API Key"
    case credentials = "Username/Password"
    
    var id: String { rawValue }
}

/// Client for UniFi Protect API (local connection)
@MainActor
final class ProtectAPIClient: ObservableObject {

    // MARK: - State

    enum ConnectionState: Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    @Published var connectionState: ConnectionState = .disconnected
    @Published var cameras: [Camera] = []
    @Published var nvrInfo: NVRInfo?

    // MARK: - Private

    private var apiKey: String?
    private var apiKeyHeaderName: String?
    private var apiKeyHeaderValue: String?
    private var csrfToken: String?
    private var authCookie: String?
    private let sslDelegate = SSLBypassDelegate()
    private var session: URLSession?
    
    // Rate limiting
    private var lastRequestTime: Date = .distantPast
    private let minRequestInterval: TimeInterval = 1.0  // minimum 1 second between requests

    init() {
        // IMPORTANT: Use ephemeral config to avoid 403 errors from stale cookies
        // URLSessionConfiguration.default can persist cookies that cause UniFi NVR
        // to reject requests with 403 Forbidden
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        // Explicitly disable all cookie handling
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        // Use dedicated queue for network operations
        let queue = OperationQueue()
        queue.name = "com.protectbar.network"
        queue.qualityOfService = .userInitiated
        self.session = URLSession(configuration: config, delegate: sslDelegate, delegateQueue: queue)
    }

    // MARK: - Authentication

    /// Authenticate using API Key (UniFi OS 3.0+)
    /// Tries multiple header formats to find the one that works
    func loginWithAPIKey(baseURL: String, apiKey: String) async throws {
        connectionState = .connecting
        
        // Try different header formats for UniFi OS API Key
        let headerFormats: [(name: String, value: String)] = [
            ("Authorization", "Bearer \(apiKey)"),
            ("X-API-KEY", apiKey),
            ("x-api-key", apiKey),
            ("Authorization", apiKey)
        ]
        
        var lastError: Error = APIError.unauthorized
        
        for (headerName, headerValue) in headerFormats {
            do {
                print("Trying API Key auth with header: \(headerName)")
                let data = try await apiKeyRequest(
                    url: baseURL + AppConstants.API.bootstrapPath,
                    method: "GET",
                    headerName: headerName,
                    headerValue: headerValue
                )
                
                // Parse bootstrap to verify it worked
                let decoder = JSONDecoder()
                let bootstrap = try decoder.decode(BootstrapResponse.self, from: data)
                
                // Success! Store the working header format
                self.apiKey = apiKey
                self.apiKeyHeaderName = headerName
                self.apiKeyHeaderValue = headerValue
                
                cameras = bootstrap.cameras.filter { $0.isConnected }
                nvrInfo = bootstrap.nvr
                
                connectionState = .connected
                print("API Key auth successful with header: \(headerName)")
                return
            } catch {
                print("API Key auth failed with header \(headerName): \(error)")
                lastError = error
                continue
            }
        }
        
        // All formats failed
        connectionState = .error(lastError.localizedDescription)
        throw lastError
    }
    
    /// Make a request with specific API key header
    private func apiKeyRequest(url: String, method: String, headerName: String, headerValue: String) async throws -> Data {
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(headerValue, forHTTPHeaderField: headerName)
        
        let (data, response) = try await session!.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                throw APIError.unauthorized
            }
            throw APIError.httpError(httpResponse.statusCode)
        }
        
        return data
    }

    /// Step 1: Fetch initial CSRF token from NVR
    private func fetchCSRFToken(baseURL: String) async throws {
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        // Disable caching to ensure we get fresh CSRF token
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        let (_, response) = try await session!.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        
        print("[CSRF] Status: \(httpResponse.statusCode)")
        print("[CSRF] Headers: \(httpResponse.allHeaderFields)")

        if let token = httpResponse.value(forHTTPHeaderField: "X-CSRF-Token") {
            csrfToken = token
            print("[CSRF] Got token: \(token.prefix(20))...")
        } else {
            print("[CSRF] No token in response!")
        }
    }

    /// Step 2: Login with credentials
    func login(baseURL: String, username: String, password: String) async throws {
        connectionState = .connecting

        do {
            guard let url = URL(string: baseURL + AppConstants.API.loginPath) else {
                throw APIError.invalidURL
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData

            struct LoginBody: Encodable {
                let username: String
                let password: String
                let rememberMe: Bool
                let token: String
            }
            let body = LoginBody(username: username, password: password, rememberMe: true, token: "")
            request.httpBody = try JSONEncoder().encode(body)

            let (data, response) = try await session!.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }

            guard httpResponse.statusCode == 200 else {
                if httpResponse.statusCode == 401 {
                    throw APIError.unauthorized
                }
                if httpResponse.statusCode == 403 {
                    throw APIError.forbidden
                }
                if httpResponse.statusCode == 429 {
                    throw APIError.rateLimited
                }
                throw APIError.httpError(httpResponse.statusCode)
            }

            // Extract updated CSRF token
            if let updatedToken = httpResponse.value(forHTTPHeaderField: "X-Updated-CSRF-Token")
                ?? httpResponse.value(forHTTPHeaderField: "X-CSRF-Token") {
                csrfToken = updatedToken
            }

            // Extract auth cookie
            if let setCookie = httpResponse.value(forHTTPHeaderField: "Set-Cookie") {
                authCookie = setCookie.components(separatedBy: ";").first
            }

            // Suppress unused variable warning - data is needed for the request but not used
            _ = data

            connectionState = .connected
        } catch {
            connectionState = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Bootstrap

    /// Fetch full system state (cameras, NVR info)
    func fetchBootstrap(baseURL: String) async throws -> BootstrapResponse {
        let data = try await authenticatedRequest(
            url: baseURL + AppConstants.API.bootstrapPath,
            method: "GET"
        )

        let decoder = JSONDecoder()
        let bootstrap = try decoder.decode(BootstrapResponse.self, from: data)

        cameras = bootstrap.cameras.filter { $0.isConnected }
        nvrInfo = bootstrap.nvr

        return bootstrap
    }

    // MARK: - Snapshots

    /// Fetch a JPEG snapshot from a camera
    func fetchSnapshot(baseURL: String, cameraId: String, width: Int = 640, height: Int = 360) async throws -> Data {
        let path = AppConstants.API.snapshotPath(cameraId: cameraId, width: width, height: height)
        return try await authenticatedRequest(url: baseURL + path, method: "GET")
    }

    // MARK: - RTSP URL Builder

    /// Build RTSP URL for a camera channel
    func rtspURL(host: String, camera: Camera, quality: StreamQuality = .low) -> String? {
        let channel: CameraChannel?
        switch quality {
        case .low: channel = camera.lowQualityChannel
        case .medium: channel = camera.mediumQualityChannel
        case .high: channel = camera.highQualityChannel
        }

        guard let ch = channel, let alias = ch.rtspAlias else { return nil }
        let port = nvrInfo?.rtspPort ?? AppConstants.defaultRTSPPort
        return AppConstants.API.rtspURL(host: host, port: port, rtspAlias: alias)
    }

    // MARK: - Connection Test

    func testConnection(baseURL: String, username: String, password: String) async -> Result<Int, Error> {
        do {
            try await login(baseURL: baseURL, username: username, password: password)
            let bootstrap = try await fetchBootstrap(baseURL: baseURL)
            return .success(bootstrap.cameras.count)
        } catch {
            return .failure(error)
        }
    }

    func testConnectionWithAPIKey(baseURL: String, apiKey: String) async -> Result<Int, Error> {
        do {
            try await loginWithAPIKey(baseURL: baseURL, apiKey: apiKey)
            return .success(cameras.count)
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Disconnect

    func disconnect() {
        apiKey = nil
        apiKeyHeaderName = nil
        apiKeyHeaderValue = nil
        csrfToken = nil
        authCookie = nil
        cameras = []
        nvrInfo = nil
        connectionState = .disconnected
    }

    // MARK: - Private Helpers

    private func authenticatedRequest(url: String, method: String) async throws -> Data {
        // Rate limiting - wait if needed
        await enforceRateLimit()
        
        guard let url = URL(string: url) else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method

        // API Key auth (preferred) - use saved header format
        if let headerName = apiKeyHeaderName, let headerValue = apiKeyHeaderValue {
            request.setValue(headerValue, forHTTPHeaderField: headerName)
        } else {
            // Cookie-based auth (fallback)
            if let csrf = csrfToken {
                request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
            }
            if let cookie = authCookie {
                request.setValue(cookie, forHTTPHeaderField: "Cookie")
            }
        }

        let (data, response) = try await session!.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Update CSRF token if provided (only for cookie auth)
        if apiKey == nil, let updatedToken = httpResponse.value(forHTTPHeaderField: "X-Updated-CSRF-Token") {
            csrfToken = updatedToken
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if httpResponse.statusCode == 401 {
                connectionState = .disconnected
                throw APIError.unauthorized
            }
            if httpResponse.statusCode == 429 {
                throw APIError.rateLimited
            }
            throw APIError.httpError(httpResponse.statusCode)
        }

        return data
    }
    
    // MARK: - Rate Limiting
    
    private func enforceRateLimit() async {
        let elapsed = Date().timeIntervalSince(lastRequestTime)
        if elapsed < minRequestInterval {
            let waitTime = minRequestInterval - elapsed
            try? await Task.sleep(nanoseconds: UInt64(waitTime * 1_000_000_000))
        }
        lastRequestTime = Date()
    }
}

// MARK: - API Errors

enum APIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case unauthorized
    case forbidden
    case rateLimited
    case httpError(Int)
    case decodingError(String)
    case connectionFailed(String)
    case networkUnavailable
    case timeout

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return L10n.Error.invalidURL
        case .invalidResponse:
            return L10n.Error.invalidResponse
        case .unauthorized:
            return L10n.Error.unauthorized
        case .forbidden:
            return L10n.Error.forbidden
        case .rateLimited:
            return L10n.Error.rateLimited
        case .httpError(let code):
            return L10n.Error.http(code)
        case .decodingError(let detail):
            return L10n.Error.decoding(detail)
        case .connectionFailed(let detail):
            return L10n.Error.connectionFailed(detail)
        case .networkUnavailable:
            return "Network unavailable. Check your connection."
        case .timeout:
            return "Request timed out. NVR may be unreachable."
        }
    }
    
    /// User-friendly help text explaining how to resolve the error
    var recoverySuggestion: String? {
        switch self {
        case .unauthorized:
            return L10n.ErrorHelp.unauthorized
        case .forbidden:
            return L10n.ErrorHelp.forbidden
        case .connectionFailed, .networkUnavailable, .timeout:
            return L10n.ErrorHelp.connection
        case .invalidURL:
            return "Enter a valid IP address (e.g., 192.168.1.1) or hostname (e.g., nvr.local)."
        case .rateLimited:
            return "The NVR is limiting requests. Wait 30 seconds before trying again."
        case .httpError(let code):
            return httpErrorHelp(code)
        default:
            return nil
        }
    }
    
    /// Icon name for the error type
    var iconName: String {
        switch self {
        case .unauthorized:
            return "key.slash"
        case .forbidden:
            return "lock.shield"
        case .rateLimited:
            return "clock.badge.exclamationmark"
        case .networkUnavailable, .connectionFailed, .timeout:
            return "wifi.exclamationmark"
        case .invalidURL:
            return "link.badge.plus"
        default:
            return "exclamationmark.triangle"
        }
    }
    
    /// Whether the error is likely temporary and user should retry
    var isRetryable: Bool {
        switch self {
        case .rateLimited, .timeout, .networkUnavailable:
            return true
        case .httpError(let code):
            return code >= 500 // Server errors are retryable
        default:
            return false
        }
    }
    
    private func httpErrorHelp(_ code: Int) -> String {
        switch code {
        case 400:
            return "Bad request. Check NVR address format."
        case 404:
            return "NVR not found. Verify the address is correct."
        case 500...599:
            return "NVR server error. Try again in a moment."
        default:
            return "Check NVR logs for more details."
        }
    }
}
