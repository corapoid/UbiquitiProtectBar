import SwiftUI
import AppKit

/// View showing recent motion and smart detection events
struct EventsView: View {
    @ObservedObject var settings: AppSettings
    let apiClient: ProtectAPIClient
    let cameras: [Camera]
    
    @State private var events: [MotionEvent] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedCamera: Camera?
    @State private var selectedEventId: String?
    @State private var thumbnails: [String: NSImage] = [:]
    
    private let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
    
    private let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Content
            if isLoading && events.isEmpty {
                loadingView
            } else if let error = errorMessage, events.isEmpty {
                errorView(error)
            } else if events.isEmpty {
                emptyView
            } else {
                eventsList
            }
        }
        .onAppear {
            Task { await loadEvents() }
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Text("Events")
                .font(.headline)
            
            Spacer()
            
            // Camera filter
            Picker("Camera", selection: $selectedCamera) {
                Text("All Cameras").tag(nil as Camera?)
                ForEach(cameras) { camera in
                    Text(camera.name).tag(camera as Camera?)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 150)
            .onChange(of: selectedCamera) { _ in
                Task { await loadEvents() }
            }
            
            // Refresh button
            Button(
                action: { Task { await loadEvents() } },
                label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                }
            )
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
    
    // MARK: - Events List
    
    private var eventsList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(events) { event in
                    EventRow(
                        event: event,
                        camera: cameras.first { $0.id == event.camera },
                        thumbnail: thumbnails[event.id],
                        isSelected: selectedEventId == event.id,
                        dateFormatter: dateFormatter,
                        relativeFormatter: relativeFormatter,
                        onTap: {
                            selectedEventId = event.id
                        }
                    )
                    .onAppear {
                        Task { await loadThumbnail(for: event) }
                    }
                }
            }
            .padding(8)
        }
    }
    
    // MARK: - States
    
    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("Loading events...")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private func errorView(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange)
            Text(error)
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Retry") {
                Task { await loadEvents() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "bell.slash")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("No recent events")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
    
    // MARK: - Data Loading
    
    private func loadEvents() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let start = Calendar.current.date(byAdding: .day, value: -1, to: Date())
            events = try await apiClient.fetchEvents(
                baseURL: settings.baseURL,
                cameraId: selectedCamera?.id,
                start: start,
                types: ["smartDetectZone", "ring"],  // Skip 'motion' events
                limit: 50
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func loadThumbnail(for event: MotionEvent) async {
        guard thumbnails[event.id] == nil,
              let thumbnailId = event.thumbnail else { return }
        
        do {
            let data = try await apiClient.fetchEventThumbnail(
                baseURL: settings.baseURL,
                thumbnailId: thumbnailId
            )
            if let image = NSImage(data: data) {
                thumbnails[event.id] = image
            }
        } catch {
            // Silently fail - thumbnail is optional
        }
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: MotionEvent
    let camera: Camera?
    let thumbnail: NSImage?
    let isSelected: Bool
    let dateFormatter: DateFormatter
    let relativeFormatter: RelativeDateTimeFormatter
    let onTap: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail or placeholder
            Group {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(
                            Image(systemName: eventIcon)
                                .foregroundColor(.secondary)
                        )
                }
            }
            .frame(width: 80, height: 45)
            .cornerRadius(6)
            
            // Event info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    // Smart detection badges
                    ForEach(event.smartTypes, id: \.rawValue) { type in
                        SmartTypeBadge(type: type)
                    }
                    
                    // Motion badge if no smart types
                    if event.smartTypes.isEmpty {
                        Label("Motion", systemImage: "waveform")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
                
                // Camera name
                Text(camera?.name ?? "Unknown Camera")
                    .font(.caption)
                    .foregroundColor(.primary)
                
                // Time
                Text(relativeFormatter.localizedString(for: event.startDate, relativeTo: Date()))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // Duration if available
            if let duration = event.duration {
                Text(formatDuration(duration))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(8)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear)
        .cornerRadius(8)
        .onTapGesture(perform: onTap)
    }
    
    private var eventIcon: String {
        if event.hasSmartDetection {
            return event.smartTypes.first?.iconName ?? "waveform"
        }
        return "waveform"
    }
    
    private func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else {
            return "\(Int(seconds / 60))m \(Int(seconds.truncatingRemainder(dividingBy: 60)))s"
        }
    }
}

// MARK: - Smart Type Badge

struct SmartTypeBadge: View {
    let type: SmartDetectType
    
    var body: some View {
        Label(type.displayName, systemImage: type.iconName)
            .font(.caption2)
            .foregroundColor(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(badgeColor)
            .cornerRadius(4)
    }
    
    private var badgeColor: Color {
        switch type {
        case .person: return .green
        case .vehicle: return .blue
        case .animal: return .orange
        case .package: return .purple
        case .licensePlate: return .indigo
        case .face: return .pink
        }
    }
}
