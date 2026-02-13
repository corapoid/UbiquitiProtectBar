import SwiftUI
import AppKit
import AVKit
import AVFoundation

/// Full-screen single camera view with timeline for playback
struct CameraDetailView: View {
    let camera: Camera
    let rtspURL: String?
    let apiClient: ProtectAPIClient
    let baseURL: String
    let onClose: () -> Void
    
    // Optional: start at specific event time
    var initialPlaybackTime: Date?
    
    @State private var isLive = true
    @State private var selectedTime = Date()
    @State private var isPlaying = true
    @State private var timelineRange: ClosedRange<Date> = {
        let now = Date()
        return now.addingTimeInterval(-3600)...now
    }()
    @State private var isLoadingPlayback = false
    @State private var playbackError: String?
    @State private var showTimeline = true
    
    @StateObject private var streamManager = RTSPStreamManager()
    @StateObject private var playbackManager = PlaybackManager()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            // Video player
            ZStack {
                if isLive {
                    livePlayerView
                } else {
                    playbackPlayerView
                }
                
                // Loading overlay
                if isLoadingPlayback {
                    Color.black.opacity(0.5)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(1.5)
                }
                
                // Error overlay
                if let error = playbackError {
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.white)
                        Button("Retry") {
                            Task { await seekToTime(selectedTime) }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(8)
                }
            }
            .aspectRatio(16/9, contentMode: .fit)
            .background(Color.black)
            
            // Timeline (only visible when not live)
            if showTimeline {
                timelineView
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if let initialTime = initialPlaybackTime {
                isLive = false
                selectedTime = initialTime
                Task { await seekToTime(initialTime) }
            }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Button(
                action: onClose,
                label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Back")
                    }
                    .font(.caption)
                }
            )
            .buttonStyle(.plain)
            
            Spacer()
            
            Text(camera.name)
                .font(.headline)
            
            Spacer()
            
            // Live/Playback toggle
            Picker("Mode", selection: $isLive) {
                Text("Live").tag(true)
                Text("Playback").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 150)
            .onChange(of: isLive) { newValue in
                if newValue {
                    playbackManager.stop()
                    playbackError = nil
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Live Player
    
    private var livePlayerView: some View {
        VLCPlayerView(
            rtspURL: rtspURL,
            cameraName: camera.name,
            streamManager: streamManager,
            apiClient: apiClient,
            baseURL: baseURL,
            cameraId: camera.id,
            isVisible: true
        )
    }
    
    // MARK: - Playback Player
    
    private var playbackPlayerView: some View {
        PlaybackVideoView(playbackManager: playbackManager)
    }
    
    // MARK: - Timeline
    
    private var timelineView: some View {
        VStack(spacing: 8) {
            // Time range selector
            HStack {
                Text(formatTime(timelineRange.lowerBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Current time display
                Text(formatTime(selectedTime))
                    .font(.caption)
                    .fontWeight(.medium)
                
                Spacer()
                
                Text(formatTime(timelineRange.upperBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            // Timeline slider
            TimelineSlider(
                value: $selectedTime,
                range: timelineRange,
                onSeek: { time in
                    Task { await seekToTime(time) }
                }
            )
            .frame(height: 40)
            
            // Time range buttons
            HStack(spacing: 12) {
                ForEach([1, 2, 6, 12, 24], id: \.self) { hours in
                    Button("\(hours)h") {
                        let now = Date()
                        timelineRange = now.addingTimeInterval(-Double(hours) * 3600)...now
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                
                Spacer()
                
                // Play/Pause for playback
                if !isLive {
                    Button(
                        action: {
                            isPlaying.toggle()
                            if isPlaying {
                                playbackManager.play()
                            } else {
                                playbackManager.pause()
                            }
                        },
                        label: {
                            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        }
                    )
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    // MARK: - Actions
    
    private func seekToTime(_ time: Date) async {
        isLoadingPlayback = true
        playbackError = nil
        
        // Load 5 minute segment around the selected time
        let start = time.addingTimeInterval(-30)
        let end = time.addingTimeInterval(270) // 5 minutes total
        
        guard let request = apiClient.authenticatedVideoExportRequest(
            baseURL: baseURL,
            cameraId: camera.id,
            start: start,
            end: end,
            channel: 1 // Medium quality for playback
        ) else {
            playbackError = "Failed to build playback URL"
            isLoadingPlayback = false
            return
        }
        
        do {
            try await playbackManager.loadVideo(request: request, seekOffset: 30) // Seek to middle
            isLoadingPlayback = false
        } catch {
            playbackError = error.localizedDescription
            isLoadingPlayback = false
        }
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

// MARK: - Timeline Slider

struct TimelineSlider: View {
    @Binding var value: Date
    let range: ClosedRange<Date>
    let onSeek: (Date) -> Void
    
    @State private var isDragging = false
    
    private var progress: Double {
        let total = range.upperBound.timeIntervalSince(range.lowerBound)
        let current = value.timeIntervalSince(range.lowerBound)
        return total > 0 ? current / total : 0
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 8)
                
                // Progress
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor)
                    .frame(width: max(0, geometry.size.width * progress), height: 8)
                
                // Thumb
                Circle()
                    .fill(Color.white)
                    .frame(width: 16, height: 16)
                    .shadow(radius: 2)
                    .offset(x: max(0, min(geometry.size.width - 16, geometry.size.width * progress - 8)))
            }
            .frame(height: geometry.size.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let percent = max(0, min(1, gesture.location.x / geometry.size.width))
                        let total = range.upperBound.timeIntervalSince(range.lowerBound)
                        value = range.lowerBound.addingTimeInterval(total * percent)
                    }
                    .onEnded { _ in
                        isDragging = false
                        onSeek(value)
                    }
            )
        }
    }
}

// MARK: - Playback Manager

@MainActor
final class PlaybackManager: ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var error: String?
    
    private var playerItem: AVPlayerItem?
    
    func loadVideo(request: URLRequest, seekOffset: TimeInterval = 0) async throws {
        // Create asset with request headers
        let asset = AVURLAsset(url: request.url!, options: [
            "AVURLAssetHTTPHeaderFieldsKey": request.allHTTPHeaderFields ?? [:]
        ])
        
        // Wait for asset to be playable
        let isPlayable = try await asset.load(.isPlayable)
        guard isPlayable else {
            throw PlaybackError.notPlayable
        }
        
        playerItem = AVPlayerItem(asset: asset)
        player = AVPlayer(playerItem: playerItem)
        
        // Seek to offset
        if seekOffset > 0 {
            await player?.seek(to: CMTime(seconds: seekOffset, preferredTimescale: 600))
        }
        
        player?.play()
        isPlaying = true
    }
    
    func play() {
        player?.play()
        isPlaying = true
    }
    
    func pause() {
        player?.pause()
        isPlaying = false
    }
    
    func stop() {
        player?.pause()
        player = nil
        playerItem = nil
        isPlaying = false
    }
    
    func seek(to time: TimeInterval) {
        player?.seek(to: CMTime(seconds: time, preferredTimescale: 600))
    }
}

enum PlaybackError: Error, LocalizedError {
    case notPlayable
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .notPlayable:
            return "Video is not playable"
        case .networkError(let detail):
            return "Network error: \(detail)"
        }
    }
}

// MARK: - Playback Video View (AVPlayer wrapper)

struct PlaybackVideoView: NSViewRepresentable {
    @ObservedObject var playbackManager: PlaybackManager
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.black.cgColor
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {
        // Remove existing player layer
        nsView.layer?.sublayers?.removeAll { $0 is AVPlayerLayer }
        
        // Add new player layer if available
        if let player = playbackManager.player {
            let playerLayer = AVPlayerLayer(player: player)
            playerLayer.frame = nsView.bounds
            playerLayer.videoGravity = .resizeAspect
            playerLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
            nsView.layer?.addSublayer(playerLayer)
        }
    }
}
