// swiftlint:disable file_length
import SwiftUI
import AppKit
import MetalKit
import Libmpv
import os.log

private let logger = Logger(subsystem: "com.protectbar", category: "MPVMetalView")

// MARK: - MPV Metal View (MTKView that renders mpv output via software rendering)

final class MPVMetalView: MTKView {
    private var mpv: OpaquePointer?
    private var mpvRenderContext: OpaquePointer?
    private var commandQueue: MTLCommandQueue?
    private var renderPipelineState: MTLRenderPipelineState?
    private var videoTexture: MTLTexture?
    private var sampler: MTLSamplerState?

    private var pixelBuffer: UnsafeMutableRawPointer?
    private var pixelBufferSize: Int = 0
    private var videoWidth: Int32 = 0
    private var videoHeight: Int32 = 0

    /// Atomic-like flags for thread-safe shutdown signaling.
    /// Both are only ever set to `true` and never back to `false`,
    /// so the worst case of a torn read is a stale `false` that
    /// causes one extra guard-return on the next iteration.
    private var isShuttingDown = false
    private var hasBeenShutDown = false

    /// Recursive lock: `draw()` is called by the display system while
    /// `renderFrame()` triggers `setNeedsDisplay`, which on some
    /// code-paths can call `draw()` synchronously on the same thread.
    /// Using NSRecursiveLock avoids deadlock.
    private let renderLock = NSRecursiveLock()

    var onStateChange: ((RTSPStreamManager.StreamState) -> Void)?

    override init(frame frameRect: CGRect, device: MTLDevice?) {
        super.init(frame: frameRect, device: device ?? MTLCreateSystemDefaultDevice())
        setupMetal()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) not implemented")
    }

    // MARK: - Metal Setup

    private func setupMetal() {
        guard let device = self.device else {
            onStateChange?(.error("Metal not available"))
            return
        }

        commandQueue = device.makeCommandQueue()

        // Configure MTKView
        colorPixelFormat = .bgra8Unorm
        framebufferOnly = false
        enableSetNeedsDisplay = true
        isPaused = true // Manual drawing
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)

        // Create shader pipeline
        setupRenderPipeline()
        setupSampler()
    }

    private func setupRenderPipeline() {
        guard let device = self.device else { return }
        renderPipelineState = Self.createRenderPipeline(device: device, pixelFormat: colorPixelFormat)
        if renderPipelineState == nil {
            onStateChange?(.error("Failed to create Metal pipeline"))
        }
    }

    private func setupSampler() {
        guard let device = self.device else { return }

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge

        sampler = device.makeSamplerState(descriptor: samplerDesc)
    }

    // MARK: - MPV Setup

    func setup(rtspURL: String) {
        guard !hasBeenShutDown else { return }
        setupMPV()
        guard mpv != nil else { return }
        setupMPVSoftwareRender()
        loadURL(rtspURL)
    }

    private func setupMPV() {
        mpv = mpv_create()
        guard mpv != nil else {
            onStateChange?(.error("Failed to create mpv instance"))
            return
        }

        // RTSP optimized settings
        setMPVOption("rtsp-transport", "tcp")
        setMPVOption("network-timeout", "10")
        setMPVOption("cache", "no")
        setMPVOption("demuxer-lavf-o", "rtsp_transport=tcp")
        setMPVOption("untimed", "yes")

        // Low latency
        setMPVOption("profile", "low-latency")
        setMPVOption("interpolation", "no")
        setMPVOption("video-sync", "audio")

        // Hardware decoding
        setMPVOption("hwdec", "videotoolbox")
        setMPVOption("vo", "libmpv")

        // No audio (security cameras)
        setMPVOption("ao", "null")
        setMPVOption("mute", "yes")

        // No OSD
        setMPVOption("osd-level", "0")
        setMPVOption("terminal", "no")
        setMPVOption("msg-level", "all=warn")

        // Keep open for reconnection
        setMPVOption("keep-open", "yes")
        setMPVOption("idle", "yes")

        // Initialize mpv
        let initResult = mpv_initialize(mpv)
        guard initResult == 0 else {
            onStateChange?(.error("mpv init failed: \(initResult)"))
            return
        }

        // Observe properties for state tracking
        mpv_observe_property(mpv, 0, "pause", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 1, "core-idle", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 2, "eof-reached", MPV_FORMAT_FLAG)
        mpv_observe_property(mpv, 3, "width", MPV_FORMAT_INT64)
        mpv_observe_property(mpv, 4, "height", MPV_FORMAT_INT64)

        // Set event callback.
        // We use passRetained so that the C callback holds a strong reference,
        // preventing `self` from being freed while mpv might still call back.
        // The matching release happens AFTER we clear the callback in shutdown().
        let wakeupCtx = Unmanaged.passRetained(self).toOpaque()
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let view = Unmanaged<MPVMetalView>.fromOpaque(ctx).takeUnretainedValue()
            // Fast non-locking check — if shutting down, skip entirely.
            guard !view.isShuttingDown else { return }
            DispatchQueue.main.async { [weak view] in
                view?.handleMPVEvents()
            }
        }, wakeupCtx)
    }

    private func setupMPVSoftwareRender() {
        guard let mpv else { return }

        // Build the params array with stable heap allocations.
        let apiTypeStr = strdup(MPV_RENDER_API_TYPE_SW)

        var apiParam = mpv_render_param()
        apiParam.type = MPV_RENDER_PARAM_API_TYPE
        apiParam.data = UnsafeMutableRawPointer(apiTypeStr)

        var endParam = mpv_render_param()
        endParam.type = MPV_RENDER_PARAM_INVALID

        var params = [apiParam, endParam]

        var renderCtx: OpaquePointer?
        let result = params.withUnsafeMutableBufferPointer { buf in
            mpv_render_context_create(&renderCtx, mpv, buf.baseAddress!)
        }

        free(apiTypeStr)

        guard result == 0, let ctx = renderCtx else {
            onStateChange?(.error("Failed to create software render context: \(result)"))
            return
        }

        mpvRenderContext = ctx

        // Render-update callback — same passRetained pattern as wakeup.
        let renderCtxPtr = Unmanaged.passRetained(self).toOpaque()
        mpv_render_context_set_update_callback(ctx, { ctx in
            guard let ctx else { return }
            let view = Unmanaged<MPVMetalView>.fromOpaque(ctx).takeUnretainedValue()
            guard !view.isShuttingDown else { return }
            DispatchQueue.main.async { [weak view] in
                view?.renderFrame()
            }
        }, renderCtxPtr)
    }

    // MARK: - Rendering

    private func renderFrame() {
        // Fast bail-out before acquiring the lock.
        guard !isShuttingDown, !hasBeenShutDown else { return }

        renderLock.lock()
        defer { renderLock.unlock() }

        // Re-check under the lock (shutdown may have run between the
        // fast-check above and the lock acquisition).
        guard !isShuttingDown, !hasBeenShutDown else { return }
        guard let renderCtx = mpvRenderContext else { return }

        // Get current render size
        let scale = window?.backingScaleFactor ?? 2.0
        let renderWidth = Int32(bounds.width * scale)
        let renderHeight = Int32(bounds.height * scale)

        guard renderWidth > 0, renderHeight > 0 else { return }

        // Allocate or resize pixel buffer
        let requiredSize = Int(renderWidth) * Int(renderHeight) * 4 // BGRA
        if pixelBuffer == nil || pixelBufferSize < requiredSize {
            pixelBuffer?.deallocate()
            pixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: 16)
            pixelBufferSize = requiredSize
        }

        videoWidth = renderWidth
        videoHeight = renderHeight

        // Build render params with heap-allocated data so pointers stay
        // valid for the entire duration of mpv_render_context_render.
        let sizePtr = UnsafeMutablePointer<Int32>.allocate(capacity: 2)
        sizePtr[0] = renderWidth
        sizePtr[1] = renderHeight

        let formatPtr = strdup("bgra")

        let stridePtr = UnsafeMutablePointer<Int>.allocate(capacity: 1)
        stridePtr.pointee = Int(renderWidth) * 4

        var sizeParam = mpv_render_param()
        sizeParam.type = MPV_RENDER_PARAM_SW_SIZE
        sizeParam.data = UnsafeMutableRawPointer(sizePtr)

        var formatParam = mpv_render_param()
        formatParam.type = MPV_RENDER_PARAM_SW_FORMAT
        formatParam.data = UnsafeMutableRawPointer(formatPtr)

        var strideParam = mpv_render_param()
        strideParam.type = MPV_RENDER_PARAM_SW_STRIDE
        strideParam.data = UnsafeMutableRawPointer(stridePtr)

        var ptrParam = mpv_render_param()
        ptrParam.type = MPV_RENDER_PARAM_SW_POINTER
        ptrParam.data = pixelBuffer

        var endParam = mpv_render_param()
        endParam.type = MPV_RENDER_PARAM_INVALID

        var renderParams = [sizeParam, formatParam, strideParam, ptrParam, endParam]
        renderParams.withUnsafeMutableBufferPointer { buf in
            _ = mpv_render_context_render(renderCtx, buf.baseAddress!)
        }

        // Free temporary allocations (after render is done).
        sizePtr.deallocate()
        free(formatPtr)
        stridePtr.deallocate()

        // Update Metal texture and schedule draw (do NOT call draw() directly)
        updateTextureAndDraw()
    }

    private func updateTextureAndDraw() {
        // Called while renderLock is held.
        guard let device = self.device,
              let pxBuf = pixelBuffer,
              videoWidth > 0, videoHeight > 0,
              !isShuttingDown else { return }

        let texW = Int(videoWidth)
        let texH = Int(videoHeight)

        // Create or update texture
        if videoTexture == nil ||
           videoTexture?.width != texW ||
           videoTexture?.height != texH {
            let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: texW,
                height: texH,
                mipmapped: false
            )
            textureDesc.usage = [.shaderRead]
            videoTexture = device.makeTexture(descriptor: textureDesc)
        }

        guard let tex = videoTexture else { return }

        // Upload pixel data to texture
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: texW, height: texH, depth: 1)
        )

        tex.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: pxBuf,
            bytesPerRow: texW * 4
        )

        // Schedule draw via display system (NEVER call draw() directly on MTKView)
        setNeedsDisplay(bounds)
    }

    override func draw(_ rect: CGRect) {
        // Protect against concurrent access to videoTexture/commandQueue/etc.
        renderLock.lock()
        defer { renderLock.unlock() }

        guard !isShuttingDown, !hasBeenShutDown else { return }

        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let cmdQueue = commandQueue,
              let pipelineState = renderPipelineState,
              let samp = sampler else { return }

        guard let commandBuffer = cmdQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        encoder.setRenderPipelineState(pipelineState)

        if let tex = videoTexture {
            encoder.setFragmentTexture(tex, index: 0)
            encoder.setFragmentSamplerState(samp, index: 0)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Load URL

    private func loadURL(_ url: String) {
        guard mpv != nil else { return }
        onStateChange?(.connecting)
        Self.sendMPVCommand(mpv!, args: ["loadfile", url])
    }

    // MARK: - Event Handling

    private func handleMPVEvents() {
        guard let mpv, !isShuttingDown, !hasBeenShutDown else { return }

        while true {
            let event = mpv_wait_event(mpv, 0)
            guard let event else { break }

            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_FILE_LOADED:
                onStateChange?(.playing)
            case MPV_EVENT_END_FILE:
                if let data = event.pointee.data {
                    let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self)
                    if endFile.pointee.reason == MPV_END_FILE_REASON_ERROR {
                        let errCode = endFile.pointee.error
                        onStateChange?(.error("Stream ended with error: \(errCode)"))
                    }
                }
            case MPV_EVENT_SHUTDOWN:
                onStateChange?(.idle)
            default:
                break
            }
        }
    }

    // MARK: - Pause/Resume

    private var isStreamPaused = false

    /// Pause the stream (stops decoding but keeps context)
    func pause() {
        guard let mpv, !isShuttingDown, !hasBeenShutDown, !isStreamPaused else { return }
        isStreamPaused = true
        Self.sendMPVCommand(mpv, args: ["set", "pause", "yes"])
    }

    /// Resume the stream
    func resume() {
        guard let mpv, !isShuttingDown, !hasBeenShutDown, isStreamPaused else { return }
        isStreamPaused = false
        Self.sendMPVCommand(mpv, args: ["set", "pause", "no"])
    }

    // MARK: - Cleanup

    func shutdown() {
        // Ensure shutdown runs exactly once.
        guard !hasBeenShutDown else { return }
        isShuttingDown = true
        hasBeenShutDown = true

        renderLock.lock()

        // 1. Tear down the render context first (stops render callbacks).
        if let ctx = mpvRenderContext {
            mpv_render_context_set_update_callback(ctx, nil, nil)
            mpv_render_context_free(ctx)
            mpvRenderContext = nil

            // Release the passRetained reference from setupMPVSoftwareRender.
            Unmanaged.passUnretained(self).release()
        }

        // 2. Tear down mpv (stops wakeup callbacks).
        if let handle = mpv {
            mpv_set_wakeup_callback(handle, nil, nil)
            mpv_terminate_destroy(handle)
            mpv = nil

            // Release the passRetained reference from setupMPV.
            Unmanaged.passUnretained(self).release()
        }

        // 3. Free pixel buffer.
        pixelBuffer?.deallocate()
        pixelBuffer = nil
        pixelBufferSize = 0

        // 4. Clear Metal resources (so draw() becomes a no-op).
        videoTexture = nil

        renderLock.unlock()

        logger.debug("MPVMetalView shutdown complete")
    }

    deinit {
        // Safety net — shutdown() is idempotent so double-call is harmless.
        shutdown()
    }

    // MARK: - Helpers

    private func setMPVOption(_ name: String, _ value: String) {
        mpv_set_option_string(mpv, name, value)
    }
}

// MARK: - Metal Pipeline & MPV Helpers

extension MPVMetalView {
    static func createRenderPipeline(
        device: MTLDevice,
        pixelFormat: MTLPixelFormat
    ) -> MTLRenderPipelineState? {
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {float2(-1,-1),float2(1,-1),float2(-1,1),float2(1,1)};
            float2 texCoords[4] = {float2(0,1),float2(1,1),float2(0,0),float2(1,0)};
            VertexOut out;
            out.position = float4(positions[vertexID], 0, 1);
            out.texCoord = texCoords[vertexID];
            return out;
        }
        fragment float4 fragmentShader(VertexOut in [[stage_in]],
                                       texture2d<float> tex [[texture(0)]],
                                       sampler samp [[sampler(0)]]) {
            return tex.sample(samp, in.texCoord);
        }
        """
        guard let library = try? device.makeLibrary(source: shaderSource, options: nil),
              let vertexFunc = library.makeFunction(name: "vertexShader"),
              let fragFunc = library.makeFunction(name: "fragmentShader") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vertexFunc
        desc.fragmentFunction = fragFunc
        desc.colorAttachments[0].pixelFormat = pixelFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    /// Send a command to mpv using a properly constructed C string array.
    /// Uses `UnsafeMutablePointer` allocation instead of `withMemoryRebound`
    /// to avoid undefined behavior from type-punning.
    static func sendMPVCommand(_ mpv: OpaquePointer, args: [String]) {
        // Allocate a contiguous C array of const-char pointers (+ nil terminator).
        let count = args.count + 1
        let cArray = UnsafeMutablePointer<UnsafePointer<CChar>?>.allocate(capacity: count)

        // Fill with strdup'd C strings.
        for (idx, arg) in args.enumerated() {
            cArray[idx] = UnsafePointer(strdup(arg))
        }
        cArray[args.count] = nil // nil terminator

        mpv_command(mpv, cArray)

        // Free all strings and the array itself.
        for idx in 0..<args.count {
            // strdup returns UnsafeMutablePointer; free via cast.
            free(UnsafeMutablePointer(mutating: cArray[idx]))
        }
        cArray.deallocate()
    }
}

// MARK: - NSViewRepresentable wrapper for SwiftUI

struct MPVPlayerNSView: NSViewRepresentable {
    let rtspURL: String
    let isVisible: Bool
    var onStateChange: ((RTSPStreamManager.StreamState) -> Void)?

    func makeNSView(context: Context) -> MPVMetalView {
        let view = MPVMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.onStateChange = onStateChange
        view.setup(rtspURL: rtspURL)
        return view
    }

    func updateNSView(_ nsView: MPVMetalView, context: Context) {
        // Pause/resume based on visibility
        if isVisible {
            nsView.resume()
        } else {
            nsView.pause()
        }
    }

    static func dismantleNSView(_ nsView: MPVMetalView, coordinator: ()) {
        nsView.shutdown()
    }
}
