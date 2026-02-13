import SwiftUI
import AppKit
import MetalKit
import Libmpv

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
    
    private var isShuttingDown = false
    private let renderLock = NSLock()
    
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
        
        // Simple vertex/fragment shaders for texture display
        let shaderSource = """
        #include <metal_stdlib>
        using namespace metal;
        
        struct VertexOut {
            float4 position [[position]];
            float2 texCoord;
        };
        
        vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
            float2 positions[4] = {
                float2(-1, -1),
                float2( 1, -1),
                float2(-1,  1),
                float2( 1,  1)
            };
            float2 texCoords[4] = {
                float2(0, 1),
                float2(1, 1),
                float2(0, 0),
                float2(1, 0)
            };
            
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
        
        do {
            let library = try device.makeLibrary(source: shaderSource, options: nil)
            let vertexFunc = library.makeFunction(name: "vertexShader")
            let fragFunc = library.makeFunction(name: "fragmentShader")
            
            let pipelineDesc = MTLRenderPipelineDescriptor()
            pipelineDesc.vertexFunction = vertexFunc
            pipelineDesc.fragmentFunction = fragFunc
            pipelineDesc.colorAttachments[0].pixelFormat = colorPixelFormat
            
            renderPipelineState = try device.makeRenderPipelineState(descriptor: pipelineDesc)
        } catch {
            onStateChange?(.error("Failed to create pipeline: \(error)"))
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
        setupMPV()
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
        
        // Set event callback
        mpv_set_wakeup_callback(mpv, { ctx in
            guard let ctx else { return }
            let view = Unmanaged<MPVMetalView>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                view.handleMPVEvents()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    private func setupMPVSoftwareRender() {
        guard let mpv else { return }
        
        // Software render parameters
        var params: [mpv_render_param] = []
        
        // API type - software
        let apiTypeStr = strdup(MPV_RENDER_API_TYPE_SW)
        defer { free(apiTypeStr) }
        
        var apiParam = mpv_render_param()
        apiParam.type = MPV_RENDER_PARAM_API_TYPE
        apiParam.data = UnsafeMutableRawPointer(apiTypeStr)
        
        var endParam = mpv_render_param()
        endParam.type = MPV_RENDER_PARAM_INVALID
        
        params = [apiParam, endParam]
        
        var renderCtx: OpaquePointer?
        let result = params.withUnsafeMutableBufferPointer { buf in
            mpv_render_context_create(&renderCtx, mpv, buf.baseAddress!)
        }
        
        guard result == 0, let ctx = renderCtx else {
            onStateChange?(.error("Failed to create software render context: \(result)"))
            return
        }
        
        mpvRenderContext = ctx
        
        // Set update callback to trigger redraws
        mpv_render_context_set_update_callback(ctx, { ctx in
            guard let ctx else { return }
            let view = Unmanaged<MPVMetalView>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async {
                view.renderFrame()
            }
        }, Unmanaged.passUnretained(self).toOpaque())
    }
    
    // MARK: - Rendering
    
    private func renderFrame() {
        guard !isShuttingDown else { return }
        
        renderLock.lock()
        defer { renderLock.unlock() }
        
        guard let mpvRenderContext else { return }
        
        // Get current render size
        let scale = window?.backingScaleFactor ?? 2.0
        let width = Int32(bounds.width * scale)
        let height = Int32(bounds.height * scale)
        
        guard width > 0, height > 0 else { return }
        
        // Allocate or resize pixel buffer
        let requiredSize = Int(width) * Int(height) * 4 // BGRA
        if pixelBuffer == nil || pixelBufferSize < requiredSize {
            pixelBuffer?.deallocate()
            pixelBuffer = UnsafeMutableRawPointer.allocate(byteCount: requiredSize, alignment: 16)
            pixelBufferSize = requiredSize
        }
        
        videoWidth = width
        videoHeight = height
        
        // Render mpv frame to pixel buffer
        var size: [Int32] = [width, height]
        var sizeParam = mpv_render_param()
        sizeParam.type = MPV_RENDER_PARAM_SW_SIZE
        sizeParam.data = withUnsafeMutablePointer(to: &size[0]) { UnsafeMutableRawPointer($0) }
        
        let format = strdup("bgra")
        defer { free(format) }
        var formatParam = mpv_render_param()
        formatParam.type = MPV_RENDER_PARAM_SW_FORMAT
        formatParam.data = UnsafeMutableRawPointer(format)
        
        var stride: Int = Int(width) * 4
        var strideParam = mpv_render_param()
        strideParam.type = MPV_RENDER_PARAM_SW_STRIDE
        strideParam.data = withUnsafeMutablePointer(to: &stride) { UnsafeMutableRawPointer($0) }
        
        var ptrParam = mpv_render_param()
        ptrParam.type = MPV_RENDER_PARAM_SW_POINTER
        ptrParam.data = pixelBuffer
        
        var endParam = mpv_render_param()
        endParam.type = MPV_RENDER_PARAM_INVALID
        
        var renderParams = [sizeParam, formatParam, strideParam, ptrParam, endParam]
        _ = renderParams.withUnsafeMutableBufferPointer { buf in
            mpv_render_context_render(mpvRenderContext, buf.baseAddress!)
        }
        
        // Update Metal texture and draw
        updateTextureAndDraw()
    }
    
    private func updateTextureAndDraw() {
        guard let device = self.device,
              let pixelBuffer,
              videoWidth > 0, videoHeight > 0 else { return }
        
        // Create or update texture
        if videoTexture == nil || 
           videoTexture?.width != Int(videoWidth) || 
           videoTexture?.height != Int(videoHeight) {
            let textureDesc = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: .bgra8Unorm,
                width: Int(videoWidth),
                height: Int(videoHeight),
                mipmapped: false
            )
            textureDesc.usage = [.shaderRead]
            videoTexture = device.makeTexture(descriptor: textureDesc)
        }
        
        guard let videoTexture else { return }
        
        // Upload pixel data to texture
        let region = MTLRegion(
            origin: MTLOrigin(x: 0, y: 0, z: 0),
            size: MTLSize(width: Int(videoWidth), height: Int(videoHeight), depth: 1)
        )
        
        videoTexture.replace(
            region: region,
            mipmapLevel: 0,
            withBytes: pixelBuffer,
            bytesPerRow: Int(videoWidth) * 4
        )
        
        // Trigger draw
        setNeedsDisplay(bounds)
        draw()
    }
    
    override func draw(_ rect: CGRect) {
        guard let drawable = currentDrawable,
              let renderPassDesc = currentRenderPassDescriptor,
              let commandQueue,
              let pipelineState = renderPipelineState,
              let sampler,
              !isShuttingDown else { return }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }
        
        encoder.setRenderPipelineState(pipelineState)
        
        if let videoTexture {
            encoder.setFragmentTexture(videoTexture, index: 0)
            encoder.setFragmentSamplerState(sampler, index: 0)
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
        
        let cmd = "loadfile"
        cmd.withCString { cmdPtr in
            url.withCString { urlPtr in
                var args: [UnsafePointer<CChar>?] = [cmdPtr, urlPtr, nil]
                _ = args.withUnsafeMutableBufferPointer { buf in
                    mpv_command(mpv, buf.baseAddress)
                }
            }
        }
    }
    
    // MARK: - Event Handling
    
    private func handleMPVEvents() {
        guard let mpv, !isShuttingDown else { return }
        
        while true {
            let event = mpv_wait_event(mpv, 0)
            guard let event else { break }
            
            switch event.pointee.event_id {
            case MPV_EVENT_NONE:
                return
            case MPV_EVENT_FILE_LOADED:
                onStateChange?(.playing)
            case MPV_EVENT_END_FILE:
                let endData = event.pointee.data?.assumingMemoryBound(to: mpv_event_end_file.self)
                if let reason = endData?.pointee.reason, reason == MPV_END_FILE_REASON_ERROR {
                    let error = endData?.pointee.error ?? 0
                    onStateChange?(.error("Stream ended with error: \(error)"))
                }
            case MPV_EVENT_SHUTDOWN:
                onStateChange?(.idle)
            default:
                break
            }
        }
    }
    
    // MARK: - Cleanup
    
    func shutdown() {
        isShuttingDown = true
        
        renderLock.lock()
        defer { renderLock.unlock() }
        
        if let mpvRenderContext {
            mpv_render_context_set_update_callback(mpvRenderContext, nil, nil)
            mpv_render_context_free(mpvRenderContext)
            self.mpvRenderContext = nil
        }
        
        if let mpv {
            mpv_set_wakeup_callback(mpv, nil, nil)
            mpv_terminate_destroy(mpv)
            self.mpv = nil
        }
        
        pixelBuffer?.deallocate()
        pixelBuffer = nil
    }
    
    deinit {
        shutdown()
    }
    
    // MARK: - Helpers
    
    private func setMPVOption(_ name: String, _ value: String) {
        mpv_set_option_string(mpv, name, value)
    }
}

// MARK: - NSViewRepresentable wrapper for SwiftUI

struct MPVPlayerNSView: NSViewRepresentable {
    let rtspURL: String
    var onStateChange: ((RTSPStreamManager.StreamState) -> Void)?
    
    func makeNSView(context: Context) -> MPVMetalView {
        let view = MPVMetalView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.onStateChange = onStateChange
        view.setup(rtspURL: rtspURL)
        return view
    }
    
    func updateNSView(_ nsView: MPVMetalView, context: Context) {
        // URL changes handled by recreating the view
    }
    
    static func dismantleNSView(_ nsView: MPVMetalView, coordinator: ()) {
        nsView.shutdown()
    }
}
