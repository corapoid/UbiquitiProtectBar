import SwiftUI
import UniformTypeIdentifiers

/// Grid view showing all cameras in a responsive layout
struct CameraGridView: View {
    @ObservedObject var viewModel: CameraGridViewModel
    @ObservedObject var settings: AppSettings
    let apiClient: ProtectAPIClient
    let onPinCamera: (Camera) -> Void
    
    @State private var showHiddenCameras = false
    @State private var draggingCamera: Camera?
    
    private let cellWidth: CGFloat = 220
    private let cellHeight: CGFloat = 124

    private var visibleCameras: [Camera] {
        let sorted = settings.sortedCameras(viewModel.cameras)
        if showHiddenCameras {
            return sorted
        }
        return sorted.filter { !settings.isCameraHidden($0.id) }
    }
    
    private var columnCount: Int {
        if settings.gridColumns == 0 {
            return max(visibleCameras.count, 1)
        }
        return settings.gridColumns
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(cellWidth), spacing: 4), count: columnCount)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Cameras")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                // Grid size toggle: 2, 4, all
                HStack(spacing: 4) {
                    gridButton(cols: 2, icon: "square.grid.2x2")
                    gridButton(cols: 4, icon: "square.grid.3x3")
                    gridButton(cols: 0, icon: "rectangle.split.1x2")
                }
                
                // Show/hide hidden cameras toggle
                if !settings.hiddenCameraIds.isEmpty {
                    Button(action: { showHiddenCameras.toggle() }, label: {
                        Image(systemName: showHiddenCameras ? "eye" : "eye.slash")
                            .font(.caption)
                            .foregroundColor(showHiddenCameras ? .accentColor : .secondary)
                    })
                    .buttonStyle(.plain)
                    .help(showHiddenCameras ? "Hide hidden cameras" : "Show hidden cameras")
                }

                // Refresh button
                Button(action: {
                    Task { await viewModel.loadCameras(settings: settings) }
                }, label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption)
                        .foregroundColor(.secondary)
                })
                .buttonStyle(.plain)
                .disabled(viewModel.isLoading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Content
            if viewModel.isLoading && viewModel.cameras.isEmpty {
                loadingView
            } else if let error = viewModel.errorMessage, viewModel.cameras.isEmpty {
                errorView(error)
            } else if visibleCameras.isEmpty {
                emptyView
            } else {
                cameraGrid
            }
        }
    }
    
    private func gridButton(cols: Int, icon: String) -> some View {
        Button(action: { settings.gridColumns = cols }, label: {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(settings.gridColumns == cols ? .accentColor : .secondary)
        })
        .buttonStyle(.plain)
        .help(cols == 0 ? "All in one row" : "\(cols) columns")
    }

    // MARK: - Grid

    private var cameraGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(visibleCameras) { camera in
                    CameraCellView(
                        camera: camera,
                        rtspURL: viewModel.rtspURL(for: camera, settings: settings),
                        apiClient: apiClient,
                        baseURL: settings.baseURL,
                        onTap: { viewModel.selectCamera(camera) },
                        onPin: { onPinCamera(camera) }
                    )
                    .frame(width: cellWidth, height: cellHeight)
                    .opacity(dragOpacity(for: camera))
                    .scaleEffect(draggingCamera?.id == camera.id ? 1.05 : 1.0)
                    .onDrag {
                        draggingCamera = camera
                        return NSItemProvider(object: camera.id as NSString)
                    }
                    .onDrop(of: [UTType.text], delegate: CameraDropDelegate(
                        camera: camera,
                        viewModel: viewModel,
                        settings: settings,
                        draggingCamera: $draggingCamera
                    ))
                    .contextMenu {
                        Button(action: { settings.toggleCameraHidden(camera.id) }, label: {
                            Label(
                                settings.isCameraHidden(camera.id) ? "Show Camera" : "Hide Camera",
                                systemImage: settings.isCameraHidden(camera.id) ? "eye" : "eye.slash"
                            )
                        })
                        Button(action: { onPinCamera(camera) }, label: {
                            Label("Pin to Desktop", systemImage: "pin")
                        })
                    }
                    .animation(.easeInOut(duration: 0.2), value: draggingCamera?.id)
                }
            }
            .padding(4)
        }
    }
    
    private func dragOpacity(for camera: Camera) -> Double {
        if let dragging = draggingCamera, dragging.id == camera.id {
            return 0.5
        }
        return settings.isCameraHidden(camera.id) ? 0.5 : 1.0
    }

    // MARK: - States

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(L10n.Grid.loading)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func errorView(_ error: String) -> some View {
        ErrorView(
            error: viewModel.lastError ?? APIError.connectionFailed(error),
            onRetry: {
                Task { await viewModel.loadCameras(settings: settings) }
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "video.slash")
                .font(.title2)
                .foregroundColor(.secondary)
            Text(L10n.Grid.empty)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(L10n.Grid.emptyHint)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Drop Delegate

struct CameraDropDelegate: DropDelegate {
    let camera: Camera
    let viewModel: CameraGridViewModel
    let settings: AppSettings
    @Binding var draggingCamera: Camera?
    
    func performDrop(info: DropInfo) -> Bool {
        draggingCamera = nil
        return true
    }
    
    func dropEntered(info: DropInfo) {
        guard let dragging = draggingCamera,
              dragging.id != camera.id else { return }
        
        viewModel.reorderCamera(dragging, toPosition: camera, settings: settings)
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
    
    func dropExited(info: DropInfo) {
        // No action needed
    }
}
