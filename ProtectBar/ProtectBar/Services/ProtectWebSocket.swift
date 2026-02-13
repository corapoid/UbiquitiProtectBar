import Foundation

/// Real-time event listener for UniFi Protect via WebSocket
/// Receives motion events, doorbell rings, and camera state changes
@MainActor
final class ProtectWebSocket: ObservableObject {

    // MARK: - Event Types

    struct MotionEvent: Sendable {
        let cameraId: String
        let cameraName: String
        let timestamp: Date
    }

    enum WebSocketState: Sendable {
        case disconnected
        case connecting
        case connected
        case error(String)
    }

    // MARK: - Published

    @Published var state: WebSocketState = .disconnected
    @Published var lastMotionEvents: [MotionEvent] = []

    // MARK: - Private

    private var webSocketTask: URLSessionWebSocketTask?
    private var session: URLSession?
    private var lastUpdateId: String?
    private var isActive = false

    var onMotionDetected: ((MotionEvent) -> Void)?

    // MARK: - Connect

    func connect(baseURL: String, csrfToken: String?, authCookie: String?, lastUpdateId: String?) {
        disconnect()
        isActive = true
        state = .connecting

        let wsURLString = baseURL
            .replacingOccurrences(of: "https://", with: "wss://")
            .replacingOccurrences(of: "http://", with: "ws://")
        let updateParam = lastUpdateId.map { "?lastUpdateId=\($0)" } ?? ""
        let fullURL = "\(wsURLString)/proxy/protect/ws/updates\(updateParam)"

        guard let url = URL(string: fullURL) else {
            state = .error("Invalid WebSocket URL")
            return
        }

        var request = URLRequest(url: url)
        if let csrf = csrfToken {
            request.setValue(csrf, forHTTPHeaderField: "X-CSRF-Token")
        }
        if let cookie = authCookie {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let sslDelegate = SSLBypassDelegate()
        let config = URLSessionConfiguration.default
        session = URLSession(configuration: config, delegate: sslDelegate, delegateQueue: nil)
        webSocketTask = session?.webSocketTask(with: request)
        webSocketTask?.resume()

        state = .connected
        receiveMessages()
    }

    // MARK: - Receive

    private func receiveMessages() {
        guard isActive else { return }

        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.isActive else { return }

                switch result {
                case .success(let message):
                    self.handleMessage(message)
                    self.receiveMessages() // Continue listening
                case .failure(let error):
                    self.state = .error(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Handle Messages

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) {
        switch message {
        case .data(let data):
            parseProtectEvent(data: data)
        case .string(let text):
            if let data = text.data(using: .utf8) {
                parseProtectEvent(data: data)
            }
        @unknown default:
            break
        }
    }

    /// UniFi Protect WebSocket uses a custom binary protocol:
    /// - 8 byte header for action frame
    /// - 8 byte header for data frame
    /// - Action JSON + Data JSON
    private func parseProtectEvent(data: Data) {
        // Minimum size: two 8-byte headers
        guard data.count > 16 else { return }

        // Action frame header (first 8 bytes)
        let actionPayloadSize = Int(data[4]) << 24 | Int(data[5]) << 16 | Int(data[6]) << 8 | Int(data[7])

        guard data.count >= 8 + actionPayloadSize + 8 else { return }

        // Action frame payload
        let actionData = data.subdata(in: 8..<(8 + actionPayloadSize))

        // Data frame header
        let dataHeaderStart = 8 + actionPayloadSize
        guard data.count > dataHeaderStart + 8 else { return }

        let dataPayloadSize = Int(data[dataHeaderStart + 4]) << 24 |
                              Int(data[dataHeaderStart + 5]) << 16 |
                              Int(data[dataHeaderStart + 6]) << 8 |
                              Int(data[dataHeaderStart + 7])

        let dataStart = dataHeaderStart + 8
        guard data.count >= dataStart + dataPayloadSize else { return }
        let eventData = data.subdata(in: dataStart..<(dataStart + dataPayloadSize))

        // Parse action JSON
        guard let actionJSON = try? JSONSerialization.jsonObject(with: actionData) as? [String: Any],
              let modelKey = actionJSON["modelKey"] as? String,
              let action = actionJSON["action"] as? String,
              let id = actionJSON["id"] as? String else {
            return
        }

        // Handle camera updates (motion detection)
        if modelKey == "camera" && action == "update" {
            if let eventJSON = try? JSONSerialization.jsonObject(with: eventData) as? [String: Any],
               let isMotionDetected = eventJSON["isMotionDetected"] as? Bool,
               isMotionDetected {

                let cameraName = (eventJSON["name"] as? String) ?? "Camera"
                let event = MotionEvent(
                    cameraId: id,
                    cameraName: cameraName,
                    timestamp: Date()
                )

                lastMotionEvents.insert(event, at: 0)
                if lastMotionEvents.count > 20 {
                    lastMotionEvents = Array(lastMotionEvents.prefix(20))
                }

                onMotionDetected?(event)
                sendMotionNotification(event)
            }
        }
    }

    // MARK: - Notifications

    private func sendMotionNotification(_ event: MotionEvent) {
        let notification = NSUserNotification()
        notification.title = "Motion Detected"
        notification.informativeText = event.cameraName
        notification.soundName = nil // Silent
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Disconnect

    func disconnect() {
        isActive = false
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        session?.invalidateAndCancel()
        session = nil
        state = .disconnected
    }
}
