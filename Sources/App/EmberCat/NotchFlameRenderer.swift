import AppKit
import MetalKit

struct NotchFlameGeometry {
    let notchWidth: CGFloat
    let notchHeight: CGFloat
    // Only the narrow outer rim needs space beside the notch; flames stay inside its width.
    let padding: CGFloat = 5
    static let maximumFlameDepth: CGFloat = 80

    var size: CGSize {
        CGSize(width: notchWidth + padding * 2, height: notchHeight + Self.maximumFlameDepth + 12)
    }
    var notch: CGRect { CGRect(x: padding, y: 0, width: notchWidth, height: notchHeight) }
    var cornerRadius: CGFloat { min(notchWidth / 2, notchHeight * 9 / 32) }
}

private struct FlameUniforms {
    var viewport: SIMD2<Float>
    var notchOrigin: SIMD2<Float>
    var notchSize: SIMD2<Float>
    var pixelScale: Float
    var time: Float
    var heat: Float
    var visibility: Float
    var drawsAnchor: Float
    var cornerRadius: Float
    var flameColor: SIMD4<Float>
    var style: SIMD4<Float>
    var motion: SIMD4<Float>
}

/// One continuous density field, shared by the live overlay and native previews.
@MainActor
final class NotchFlameRenderer {
    let device: MTLDevice
    private let queue: MTLCommandQueue
    private let pipeline: MTLRenderPipelineState
    private let noise: MTLTexture

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw Self.error("Metal is unavailable")
        }
        self.device = device
        self.queue = queue
        let texture = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: 128, height: 128, mipmapped: false)
        texture.storageMode = .shared
        texture.usage = .shaderRead
        guard let noise = device.makeTexture(descriptor: texture) else {
            throw Self.error("Could not allocate flame noise")
        }
        self.noise = noise
        var seed: UInt32 = 0x6c3e2d71
        var bytes = [UInt8](repeating: 0, count: 128 * 128 * 4)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            for channel in 0..<2 {
                seed ^= seed << 13
                seed ^= seed >> 17
                seed ^= seed << 5
                bytes[offset + channel] = UInt8(seed >> 24)
            }
            bytes[offset + 3] = 255
        }
        bytes.withUnsafeBytes {
            noise.replace(region: MTLRegionMake2D(0, 0, 128, 128), mipmapLevel: 0,
                withBytes: $0.baseAddress!, bytesPerRow: 128 * 4)
        }
        let library = try device.makeLibrary(source: NotchFlameShader.source, options: nil)
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "flameVertex")
        descriptor.fragmentFunction = library.makeFunction(name: "flameFragment")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func draw(texture: MTLTexture, geometry: NotchFlameGeometry, time: Double,
              heat: Float, visibility: Float = 1, drawsAnchor: Bool = false,
              color: SIMD3<Float> = NotchFlamePalette.standard.color(for: 180),
              appearance: NotchFlameAppearance = .standard,
              reduceMotion: Bool = false, drawable: CAMetalDrawable? = nil,
              wait: Bool = false) throws {
        guard let command = queue.makeCommandBuffer() else { throw Self.error("No command buffer") }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            throw Self.error("No render encoder")
        }
        var uniforms = FlameUniforms(
            viewport: SIMD2(Float(geometry.size.width), Float(geometry.size.height)),
            notchOrigin: SIMD2(Float(geometry.notch.minX), Float(geometry.notch.minY)),
            notchSize: SIMD2(Float(geometry.notchWidth), Float(geometry.notchHeight)),
            pixelScale: Float(texture.width) / Float(geometry.size.width),
            time: Float(reduceMotion ? 8.73 : time),
            heat: heat, visibility: visibility, drawsAnchor: drawsAnchor ? 1 : 0,
            cornerRadius: Float(geometry.cornerRadius),
            flameColor: SIMD4(color.x, color.y, color.z, 1),
            style: SIMD4(Float(appearance.brightness), Float(appearance.core),
                Float(appearance.transparency), Float(appearance.length)),
            motion: SIMD4(Float(appearance.turbulence), 0, 0, 0))
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<FlameUniforms>.stride, index: 0)
        encoder.setFragmentTexture(noise, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
        if let drawable { command.present(drawable) }
        command.commit()
        if wait {
            command.waitUntilCompleted()
            if let error = command.error { throw error }
        }
    }

    func image(geometry: NotchFlameGeometry, time: Double, speed: Double,
               scale: CGFloat = 2, active: Bool = true, drawsAnchor: Bool = false,
               palette: NotchFlamePalette = .standard,
               color: SIMD3<Float>? = nil, appearance: NotchFlameAppearance = .standard,
               visibility: Float = 1,
               reduceMotion: Bool = false) throws -> CGImage {
        let width = Int((geometry.size.width * scale).rounded())
        let height = Int((geometry.size.height * scale).rounded())
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: width, height: height, mipmapped: false)
        descriptor.usage = .renderTarget
        descriptor.storageMode = .shared
        guard let texture = device.makeTexture(descriptor: descriptor) else {
            throw Self.error("Could not allocate preview texture")
        }
        let heat = Float(NotchFlameAnimation.heat(for: speed))
        try draw(texture: texture, geometry: geometry, time: time,
            heat: heat, visibility: active && heat > 0 ? visibility : 0,
            drawsAnchor: drawsAnchor, color: color ?? palette.color(for: speed),
            appearance: appearance, reduceMotion: reduceMotion, wait: true)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        pixels.withUnsafeMutableBytes {
            texture.getBytes($0.baseAddress!, bytesPerRow: width * 4,
                from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width, height: height, bitsPerComponent: 8,
                bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue)
                    .union(.byteOrder32Little), provider: provider,
                decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { throw Self.error("Could not encode preview image") }
        return image
    }

    private static func error(_ description: String) -> NSError {
        NSError(domain: "EmberCat.Flame", code: 1,
            userInfo: [NSLocalizedDescriptionKey: description])
    }
}

@MainActor
final class NotchFlameMetalView: MTKView, MTKViewDelegate {
    var geometry: NotchFlameGeometry
    var drawsAnchor = false
    var onFadeOut: (() -> Void)?
    var onRenderFailure: (() -> Void)?
    private let renderer: NotchFlameRenderer
    private var animation = NotchFlameAnimation()
    private var lastTime = ProcessInfo.processInfo.systemUptime
    private var accessibilityObserver: NSObjectProtocol?
    private(set) var palette: NotchFlamePalette = .standard
    private(set) var flameAppearance: NotchFlameAppearance = .standard
    private var lastSpeed: Double = 0
    private var lastActive = true
    private(set) var renderedFrameCount: UInt64 = 0
    private var frameLink: CADisplayLink?
    var isRendering: Bool { frameLink != nil }

    init(geometry: NotchFlameGeometry, renderer: NotchFlameRenderer? = nil) throws {
        self.geometry = geometry
        let renderer = try renderer ?? NotchFlameRenderer()
        self.renderer = renderer
        super.init(frame: CGRect(origin: .zero, size: geometry.size), device: renderer.device)
        colorPixelFormat = .bgra8Unorm
        clearColor = MTLClearColorMake(0, 0, 0, 0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 60
        autoResizeDrawable = false
        enableSetNeedsDisplay = false
        isPaused = true
        delegate = self
        refreshDisplay()
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override var isOpaque: Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        refreshDisplay()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        pauseFrames()
        refreshDisplay()
        if window != nil { resumeIfNeeded() }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        refreshDisplay()
    }

    func refreshDisplay(maximumFramesPerSecond: Int? = nil) {
        let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        if drawableSize != size { drawableSize = size }
        preferredFramesPerSecond = NotchDisplayProfile.frameRate(
            for: maximumFramesPerSecond ?? window?.screen?.maximumFramesPerSecond ?? 60)
        updateFrameRate()
        // A paused reduced-motion surface still needs one redraw after a resize or display change.
        if !isRendering, !animation.isHidden { draw() }
    }

    func setSpeed(_ speed: Double, active: Bool = true) {
        lastSpeed = speed
        lastActive = active
        animation.setSpeed(speed, active: active, color: palette.color(for: speed))
        if accessibilityObserver == nil {
            accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.resumeIfNeeded() }
            }
        }
        resumeIfNeeded()
    }

    func setPalette(_ palette: NotchFlamePalette) {
        guard palette != self.palette, palette.validationError == nil else { return }
        self.palette = palette
        setSpeed(lastSpeed, active: lastActive)
    }

    func setAppearance(_ appearance: NotchFlameAppearance) {
        guard appearance != flameAppearance, appearance.validationError == nil else { return }
        flameAppearance = appearance
        // Reduced motion still updates an edited material once without starting a loop.
        if !isRendering, !animation.isHidden { draw() }
    }

    private func resumeIfNeeded() {
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        guard animation.needsFrames(reduceMotion: reduced) else { pauseFrames(); return }
        guard frameLink == nil, window != nil else { return }
        lastTime = ProcessInfo.processInfo.systemUptime
        // MTKView's internal loop can remain stopped after a preview window closes.
        // Own the display link so editing, tracking and reopening share one lifecycle.
        frameLink = displayLink(target: self, selector: #selector(displayFrame(_:)))
        updateFrameRate()
        frameLink?.add(to: .main, forMode: .common)
    }

    private func updateFrameRate() {
        let fps = Float(preferredFramesPerSecond)
        frameLink?.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, fps), maximum: fps, preferred: fps)
    }

    @objc private func displayFrame(_ link: CADisplayLink) {
        draw()
    }

    private func pauseFrames() {
        frameLink?.invalidate()
        frameLink = nil
    }

    func stop() {
        pauseFrames()
        animation.reset()
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        let now = ProcessInfo.processInfo.systemUptime
        let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animation.advance(by: now - lastTime, reduceMotion: reduced, flow: flameAppearance.flow)
        lastTime = now
        guard let drawable = currentDrawable else {
            if animation.isHidden { pauseFrames(); onFadeOut?() }
            return
        }
        do {
            try renderer.draw(texture: drawable.texture, geometry: geometry,
                time: animation.phase, heat: Float(animation.heat),
                visibility: Float(animation.visibility), drawsAnchor: drawsAnchor,
                color: animation.color, appearance: flameAppearance,
                reduceMotion: reduced, drawable: drawable)
            renderedFrameCount &+= 1
        } catch {
            NSLog("EmberCat flame frame: %@", error.localizedDescription)
            stop()
            onRenderFailure?()
            return
        }
        if !animation.needsFrames(reduceMotion: reduced) {
            pauseFrames()
            if animation.isHidden { onFadeOut?() }
        }
    }
}
