import AppKit
import SwiftUI
import AgentPetCore

/// A replay is local presentation only. It never changes receipts or sends a gesture.
@MainActor
final class PetPairInteractionPlayer: ObservableObject {
    struct Playback: Identifiable {
        let id = UUID()
        let message: PetRelayMessage
    }
    @Published private(set) var active: Playback?
    private(set) var pending: [PetRelayMessage] = []

    func enqueue(_ messages: [PetRelayMessage]) {
        let existing = Set(pending.map(\.id) + [active?.message.id].compactMap { $0 })
        pending.append(contentsOf: messages.filter { $0.interaction != nil && !existing.contains($0.id) })
        advance()
    }

    func replay(_ message: PetRelayMessage) {
        guard message.interaction != nil else { return }
        pending.removeAll { $0.id == message.id }
        active = Playback(message: message)
    }

    func finish(_ id: UUID) {
        guard active?.id == id else { return }
        active = nil
        advance()
    }

    func retain(_ ids: Set<String>) {
        pending.removeAll { !ids.contains($0.id) }
        if let active, !ids.contains(active.message.id) { self.active = nil }
        advance()
    }

    func stop() { pending = []; active = nil }

    private func advance() {
        guard active == nil, !pending.isEmpty else { return }
        active = Playback(message: pending.removeFirst())
    }
}

/// Shared choreography for live playback and deterministic, offscreen frame rendering.
enum PetPairMotion {
    static let duration: TimeInterval = 3.6
    struct Sample {
        let distance: CGFloat
        let localShift: CGFloat
        let localTilt: CGFloat
        let visitorLift: CGFloat
        let opacity: Float
        let pose: Int?
        let affection: Float
    }

    static func sample(_ gesture: PetRelayGesture, at time: TimeInterval) -> Sample {
        func ease(_ start: Double, _ end: Double) -> Double {
            let value = min(1, max(0, (time - start) / (end - start)))
            return value * value * (3 - 2 * value)
        }
        let arrival = ease(0.05, 0.85)
        let departure = ease(2.65, duration)
        let contact = ease(0.90, 1.16) * (1 - ease(2.12, 2.55))
        let near = gesture == .hug ? 0.39 : gesture == .poke ? 0.56 : 0.74
        let distance = 1.23 + (near - 1.23) * arrival + (1.23 - near) * departure
        let recoil = gesture == .poke ? -0.07 * contact : gesture == .hug ? 0.025 * contact : 0
        let walking = time < 0.85 || time > 2.65
        let lift = walking ? abs(sin(time * .pi * 4)) * 0.025 : 0
        let pose: Int? = time < 0.48 || time > 2.95 ? nil
            : time < 0.85 ? 0 : time < 1.12 ? 1 : time < 1.40 ? 2 : time < 2.15 ? 3 : time < 2.55 ? 4 : 5
        return Sample(distance: distance, localShift: recoil,
                      localTilt: (gesture == .poke ? -0.12 : 0.035) * contact,
                      visitorLift: lift, opacity: Float(ease(0, 0.22) * (1 - ease(3.13, duration))),
                      pose: pose, affection: gesture == .hug ? Float(contact) : 0)
    }
}

/// Optional side-facing poses live beside existing packs, leaving imported appearances intact.
@MainActor
enum PetPairPoseLibrary {
    private static var cache: [URL: [[NSImage]]] = [:]
    static func load(_ pack: ImagePetPack) -> [[NSImage]]? {
        let url = pack.directory.appendingPathComponent("pair-interactions.png")
        if let cached = cache[url] { return cached }
        guard let image = NSImage(contentsOf: url),
              let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              cg.width == 1536, cg.height == 1024 else { return nil }
        let rows = (0..<4).map { row in
            (0..<6).compactMap { col -> NSImage? in
                guard let frame = cg.cropping(to: CGRect(x: col * 256, y: row * 256, width: 256, height: 256)) else { return nil }
                return NSImage(cgImage: frame, size: NSSize(width: 256, height: 256))
            }
        }
        guard rows.allSatisfy({ $0.count == 6 }) else { return nil }
        cache[url] = rows
        return rows
    }
}

@MainActor
struct PetPairArtwork {
    let localIdle: NSImage
    let visitorIdle: NSImage
    let localPoses: [NSImage]
    let visitorPoses: [NSImage]

    init?(local: ImagePetPack, message: PetRelayMessage) {
        guard let localIdle = local.restingFrames.first, let gesture = message.interaction else { return nil }
        self.localIdle = localIdle
        let visitor = PetRelayAppearance.pack(for: message.senderPet)
        visitorIdle = visitor?.restingFrames.first ?? PetRelayAppearance.portrait(for: message.senderPet)
            ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil) ?? localIdle
        let receiverRow = gesture == .hug ? 1 : 3
        let visitorRow = gesture == .hug ? 0 : 2
        // Only actual matching artwork is used. A custom pet responds with its own idle sprite.
        localPoses = gesture == .peek ? local.interactionClips[.peek]?.frames ?? []
            : PetPairPoseLibrary.load(local)?[receiverRow] ?? []
        visitorPoses = gesture == .peek ? visitor?.interactionClips[.peek]?.frames ?? []
            : visitor.flatMap { PetPairPoseLibrary.load($0)?[visitorRow] } ?? []
    }
}

struct PetPairSceneView: NSViewRepresentable {
    let artwork: PetPairArtwork
    let playback: PetPairInteractionPlayer.Playback
    let petSize: CGFloat
    var localOffset: CGFloat = 0
    /// The visitor enters from the side with room, without moving the home pet's anchor.
    var visitorOnRight = false
    let onCompletion: (UUID) -> Void

    func makeNSView(context: Context) -> PetPairStageNSView { PetPairStageNSView() }
    func updateNSView(_ view: PetPairStageNSView, context: Context) {
        view.configure(artwork: artwork, gesture: playback.message.interaction ?? .poke,
                       playbackID: playback.id, petSize: petSize, localOffset: localOffset,
                       visitorOnRight: visitorOnRight, onCompletion: onCompletion)
    }
    static func dismantleNSView(_ view: PetPairStageNSView, coordinator: ()) { view.teardown() }
}

/// A short-lived 30fps CALayer scene. No SwiftUI per-frame updates and no idle scene timer.
final class PetPairStageNSView: NSView {
    private let receiver = CALayer()
    private let visitor = CALayer()
    private let heart = CATextLayer()
    private var artwork: PetPairArtwork?
    private var gesture: PetRelayGesture = .poke
    private var playbackID: UUID?
    private var timer: Timer?
    private var startedAt: TimeInterval = 0
    private var petSize: CGFloat = 120
    private var localOffset: CGFloat = 0
    private var visitorOnRight = false
    private var completion: ((UUID) -> Void)?
    private(set) var elapsed: TimeInterval = 0
    var isAnimating: Bool { timer != nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        for sprite in [receiver, visitor] {
            sprite.contentsGravity = .resizeAspect
            sprite.contentsScale = 2
            sprite.magnificationFilter = .linear
            sprite.minificationFilter = .linear
            layer?.addSublayer(sprite)
        }
        heart.string = "♥"
        heart.fontSize = 16
        heart.alignmentMode = .center
        heart.foregroundColor = NSColor.systemPink.cgColor
        heart.contentsScale = 2
        layer?.addSublayer(heart)
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

    func configure(artwork: PetPairArtwork, gesture: PetRelayGesture, playbackID: UUID,
                   petSize: CGFloat, localOffset: CGFloat = 0, visitorOnRight: Bool = false,
                   animate: Bool = true, onCompletion: @escaping (UUID) -> Void) {
        self.artwork = artwork; self.gesture = gesture; self.petSize = petSize
        self.localOffset = localOffset; self.visitorOnRight = visitorOnRight
        self.completion = onCompletion
        guard self.playbackID != playbackID else { render(at: elapsed); return }
        teardown()
        self.playbackID = playbackID
        startedAt = ProcessInfo.processInfo.systemUptime
        render(at: 0)
        guard animate else { return }
        let identity = playbackID
        let timer = Timer(timeInterval: 1 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.playbackID == identity, self.timer != nil else { return }
                let time = ProcessInfo.processInfo.systemUptime - self.startedAt
                self.render(at: time)
                if time >= PetPairMotion.duration {
                    self.teardown()
                    self.completion?(identity)
                }
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    override func layout() { super.layout(); render(at: elapsed) }

    func render(at time: TimeInterval) {
        guard let artwork else { return }
        elapsed = time
        let sample = PetPairMotion.sample(gesture, at: time)
        let side: CGFloat = visitorOnRight ? 1 : -1
        let home = CGPoint(x: bounds.midX + localOffset, y: petSize / 2)
        func image(_ frames: [NSImage], idle: NSImage) -> NSImage {
            guard let pose = sample.pose, frames.indices.contains(pose) else { return idle }
            return frames[pose]
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let receiverImage = image(artwork.localPoses, idle: artwork.localIdle)
        let visitorImage = image(artwork.visitorPoses, idle: artwork.visitorIdle)
        receiver.contents = receiverImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        visitor.contents = visitorImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        for sprite in [receiver, visitor] { sprite.bounds = CGRect(x: 0, y: 0, width: petSize, height: petSize) }
        let recipientX = min(bounds.width - petSize / 2,
                             max(petSize / 2, home.x + side * sample.localShift * petSize))
        receiver.position = CGPoint(x: recipientX, y: home.y)
        visitor.position = CGPoint(x: home.x + side * sample.distance * petSize,
                                   y: home.y + sample.visitorLift * petSize)
        // Authored actor faces right and recipient faces left. Mirror together for right entry.
        let mirror: CGFloat = visitorOnRight ? -1 : 1
        receiver.setAffineTransform(CGAffineTransform(rotationAngle: -side * sample.localTilt)
            .scaledBy(x: artwork.localPoses.isEmpty ? 1 : mirror, y: 1))
        visitor.setAffineTransform(CGAffineTransform(scaleX: artwork.visitorPoses.isEmpty ? 1 : mirror, y: 1))
        visitor.opacity = sample.opacity
        heart.frame = CGRect(x: home.x + side * sample.distance * petSize / 2 - 12,
                             y: petSize * 0.76, width: 24, height: 24)
        heart.opacity = sample.affection
        CATransaction.commit()
    }

    /// Use the exact live scene's layers for QA without showing a window or running a timer.
    func snapshot(at time: TimeInterval, scale: CGFloat = 2) -> NSBitmapImageRep? {
        render(at: time)
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap)?.cgContext else { return nil }
        context.scaleBy(x: scale, y: scale)
        layer?.render(in: context)
        return bitmap
    }

    func teardown() { timer?.invalidate(); timer = nil; playbackID = nil }
}

/// Each received interaction keeps its own replay and close controls, even after expiry/restart.
struct PetInteractionBubbles: View {
    let messages: [PetRelayMessage]
    var canReplay = true
    let replay: (PetRelayMessage) -> Void
    let close: (String) -> Void

    var body: some View {
        let interactions = messages.filter { $0.interaction != nil }
        if !interactions.isEmpty {
            ScrollView {
                VStack(spacing: 5) {
                    ForEach(interactions) { message in
                        HStack(spacing: 5) {
                            Button { replay(message) } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "play.circle.fill").foregroundStyle(.pink)
                                    Text(verbatim: message.interactionBubbleText).lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Spacer(minLength: 0)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).disabled(!canReplay)
                            .help(InterfaceText.format(canReplay ? "Replay this interaction" : "Enable animations to replay"))
                            .accessibilityIdentifier("relay-replay-" + message.id)
                            Button { close(message.id) } label: {
                                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
                                    .padding(5).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).help("Close this interaction")
                            .accessibilityIdentifier("relay-close-interaction-" + message.id)
                        }
                        .font(.system(size: 12, weight: .medium))
                        .padding(.leading, 11).padding(.trailing, 5).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.pink.opacity(0.3)))
                    }
                }
                .padding(2)
            }
            .scrollIndicators(.hidden)
            .frame(width: 270, height: min(144, interactions.reduce(CGFloat(0)) {
                $0 + ($1.interactionBubbleText.count > 17 ? 52 : 43)
            }))
            .accessibilityIdentifier("relay-interaction-bubbles")
        }
    }
}

extension PetRelayMessage {
    var interactionBubbleText: String {
        let nickname = senderPet?.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (nickname?.isEmpty == false ? nickname! : senderName)
        let key: String
        switch interaction {
        case .hug: key = "%@ gave you a hug"
        case .poke: key = "%@ gave you a poke"
        case .peek: key = "%@ peeked at you"
        case nil: return displayContent
        }
        return String(format: NSLocalizedString(key, comment: "replay bubble"), name)
    }
}
