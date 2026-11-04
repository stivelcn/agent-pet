import SwiftUI
import AppKit

/// Renders an imported spritesheet pet. The frame cycling runs in a CALayer
/// (see `SpriteLayerNSView`), NOT a SwiftUI `TimelineView`: a SwiftUI timeline
/// re-evaluates and re-renders the whole view tree every tick, and an
/// always-on-screen pet (×every window) made that the dominant CPU cost.
/// Swapping `layer.contents` on a timer animates in Core Animation instead, so
/// SwiftUI does not redraw the sprite per frame. The renderer intentionally
/// has no task-mood input or celebration overlay: all states stay restful.
struct ImageSpriteView: View {
    /// In-place idle/blink frames, resolved by the caller.
    let frames: [NSImage]
    /// Sprite frame rate supplied by the caller (from `PetController.spriteFPS(forMood:)`).
    let fps: Double
    var size: CGFloat = 110
    var frameDurations: [TimeInterval]? = nil
    @Environment(\.animationsEnabled) private var animationsEnabled

    var body: some View {
        ZStack {
            if frames.isEmpty {
                Image(systemName: "pawprint.fill").font(.system(size: 36))
            } else {
                SpriteLayer(frames: frames, fps: fps, size: size, frameDurations: frameDurations, animate: animationsEnabled)
                    .frame(width: size, height: size)
            }
        }
        .frame(width: size, height: size)
    }
}

/// SwiftUI bridge to the CALayer-backed sprite player.
private struct SpriteLayer: NSViewRepresentable {
    let frames: [NSImage]
    let fps: Double
    let size: CGFloat
    let frameDurations: [TimeInterval]?
    var animate: Bool = true

    func makeNSView(context: Context) -> SpriteLayerNSView {
        let view = SpriteLayerNSView()
        view.configure(frames: frames, fps: fps, animate: animate, frameDurations: frameDurations)
        return view
    }

    func updateNSView(_ view: SpriteLayerNSView, context: Context) {
        // Called on every SwiftUI re-render of the parent (which, while a chat
        // bubble's perpetual animations run, can be ~display-rate). `configure`
        // is idempotent: it only rebuilds frames / restarts the timer when the
        // frames or fps actually change, so this never churns the timer.
        view.configure(frames: frames, fps: fps, animate: animate, frameDurations: frameDurations)
    }

    static func dismantleNSView(_ view: SpriteLayerNSView, coordinator: ()) {
        view.teardown()
    }
}

/// A layer-backed view that cycles CGImages by swapping `layer.contents` on a
/// timer at `fps`. No SwiftUI involvement per frame.
final class SpriteLayerNSView: NSView {
    private var cgFrames: [CGImage] = []
    private var sourceFrames: [NSImage] = []
    private var fps: Double = 3
    private var animate: Bool = true
    private var index = 0
    private var timer: Timer?
    private var frameDurations: [TimeInterval]?
    private var timerGeneration = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.magnificationFilter = .linear
        layer?.minificationFilter = .linear
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(frames: [NSImage], fps: Double, animate: Bool = true,
                   frameDurations: [TimeInterval]? = nil) {
        let framesChanged = frames.count != sourceFrames.count
            || !zip(frames, sourceFrames).allSatisfy { $0 === $1 }
        if framesChanged {
            sourceFrames = frames
            cgFrames = frames.compactMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
            index = 0
        }
        let validDurations = frameDurations.flatMap { values in
            values.count == frames.count && values.allSatisfy { $0.isFinite && $0 > 0 } ? values : nil
        }
        let timingChanged = validDurations != self.frameDurations
        self.frameDurations = validDurations
        let fpsChanged = fps != self.fps
        self.fps = fps
        let animateChanged = animate != self.animate
        self.animate = animate
        if framesChanged || fpsChanged || animateChanged || timingChanged {
            restartTimer()
        }
    }

    /// Authored timing is at the normal quiet speed (2 fps preference). Sleepy
    /// and slower preferences scale the whole loop instead of stretching blinks equally.
    func frameDuration(at frame: Int) -> TimeInterval {
        let safeFPS = fps.isFinite && fps > 0 ? fps : 2
        if let frameDurations, frameDurations.indices.contains(frame) {
            return frameDurations[frame] * 2 / safeFPS
        }
        return 1 / safeFPS
    }

    private func restartTimer() {
        teardown()
        if !animate { index = 0 }
        showCurrent()
        scheduleNextFrame()
    }

    private func scheduleNextFrame() {
        guard animate, cgFrames.count > 1, fps.isFinite, fps > 0 else { return }
        let generation = timerGeneration
        let t = Timer(timeInterval: frameDuration(at: index), repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.timerGeneration == generation else { return }
                self.index = (self.index + 1) % self.cgFrames.count
                self.showCurrent()
                self.scheduleNextFrame()
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func showCurrent() {
        guard !cgFrames.isEmpty else { layer?.contents = nil; return }
        layer?.contents = cgFrames[index % cgFrames.count]
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        layer?.contentsScale = window?.backingScaleFactor ?? 2
    }

    /// Stops the frame timer. Called from `SpriteLayer.dismantleNSView` when the
    /// SwiftUI view is removed (Swift 6 forbids touching the non-Sendable timer
    /// from a nonisolated `deinit`).
    func teardown() {
        timerGeneration += 1
        timer?.invalidate()
        timer = nil
    }
}
