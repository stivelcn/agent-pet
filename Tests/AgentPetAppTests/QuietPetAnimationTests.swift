import AppKit
import QuartzCore
import Testing
@testable import agentpet
@testable import AgentPetCore

@MainActor
@Suite(.serialized)
struct QuietPetAnimationTests {
    private func frame(_ color: NSColor) throws -> NSImage {
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        return NSImage(cgImage: try #require(context.makeImage()), size: NSSize(width: 8, height: 8))
    }

    private func pack(_ clips: [[NSImage]], id: String = "isolated-quiet-pet") -> ImagePetPack {
        ImagePetPack(id: id, displayName: "Quiet test pet", description: nil,
                     clips: clips, directory: URL(fileURLWithPath: "/isolated-synthetic-pet"))
    }

    private func restoreFPS(_ saved: Any?) {
        if let saved {
            LocalPreferences.defaults.set(saved, forKey: "agentpet.animationFPS")
        } else {
            LocalPreferences.defaults.removeObject(forKey: "agentpet.animationFPS")
        }
    }

    private func displayedFrame(_ view: SpriteLayerNSView) throws -> ObjectIdentifier {
        ObjectIdentifier(try #require(view.layer?.contents as AnyObject?))
    }

    private func waitForNextFrame(_ view: SpriteLayerNSView, after previous: ObjectIdentifier) async throws {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if try displayedFrame(view) != previous { return }
            try await Task.sleep(for: .milliseconds(40))
        }
        Issue.record("The idle loop must still animate; quiet mode must not freeze blinking")
    }

    @Test func restingFramesPreserveTheEntireIdleAndBlinkLoop() throws {
        let open = try frame(.red)
        let closed = try frame(.green)
        let running = try frame(.blue)
        let pet = pack([[open, closed, open], [running], [running]])
        #expect(pet.restingFrames.count == 3)
        #expect(pet.restingFrames[0] === open)
        #expect(pet.restingFrames[1] === closed)
        #expect(pet.restingFrames[2] === open)
        #expect(!pet.restingFrames.contains { $0 === running })
    }

    @Test func missingIdleNeverFallsBackToARunningClip() throws {
        #expect(pack([]).restingFrames.isEmpty)
        #expect(pack([[], [try frame(.blue)]]).restingFrames.isEmpty)
    }

    @Test func oldSavedActionBindingsCannotReplaceTheRestingLoop() throws {
        let id = "isolated-quiet-pet-\(UUID().uuidString)"
        let preferenceKey = "agentpet.bindings.\(id)"
        defer { LocalPreferences.defaults.removeObject(forKey: preferenceKey) }
        let idle = try frame(.red)
        let action = try frame(.blue)
        let pet = pack([[idle]] + Array(repeating: [action], count: 8), id: id)
        // Isolated synthetic fixture in the old on-disk format. Compatibility must
        // not require shipping the retired action-binding store in production.
        let legacyBindings = Dictionary(uniqueKeysWithValues:
            PetMood.allCases.enumerated().map { ($0.element.rawValue, $0.offset + 1) })
        let saved = try JSONEncoder().encode(legacyBindings)
        LocalPreferences.defaults.set(saved, forKey: preferenceKey)
        let persisted = try #require(LocalPreferences.defaults.data(forKey: preferenceKey))
        let reloaded = try JSONDecoder().decode([String: Int].self, from: persisted)
        for mood in PetMood.allCases {
            #expect(try #require(reloaded[mood.rawValue]) > 0)
            #expect(pet.restingFrames.count == 1)
            #expect(pet.restingFrames[0] === idle)
        }
        #expect(LocalPreferences.defaults.data(forKey: preferenceKey) == saved)
    }

    @Test func everyTaskStateIncludingCompletionUsesTheIdleCadence() {
        let saved = LocalPreferences.defaults.object(forKey: "agentpet.animationFPS")
        defer { restoreFPS(saved) }
        let controller = PetController()
        for speed in [1.0, 2.0] {
            controller.animationFPS = speed
            for mood in PetMood.allCases where mood != .sleepy {
                #expect(controller.spriteFPS(forMood: mood) == speed)
            }
        }
    }

    @Test func sleepySlowsTheSameIdleLoopWithoutSelectingSadOrRunningActions() throws {
        let saved = LocalPreferences.defaults.object(forKey: "agentpet.animationFPS")
        defer { restoreFPS(saved) }
        let controller = PetController()
        controller.animationFPS = 2
        let idle = try frame(.red)
        let blink = try frame(.green)
        let pet = pack([[idle, blink], [try frame(.blue)]])
        let sleepyView = ImageSpriteView(frames: pet.restingFrames,
                                        fps: controller.spriteFPS(forMood: .sleepy))
        #expect(sleepyView.fps == 1)
        #expect(sleepyView.fps < controller.spriteFPS(forMood: .idle))
        #expect(sleepyView.frames[0] === idle)
        #expect(sleepyView.frames[1] === blink)
    }

    @Test func legacyFastPreferenceIsClampedWithoutRewritingItOnLoad() {
        let saved = LocalPreferences.defaults.object(forKey: "agentpet.animationFPS")
        defer { restoreFPS(saved) }
        LocalPreferences.defaults.set(12.0, forKey: "agentpet.animationFPS")
        let controller = PetController()
        #expect(controller.animationFPS == 2)
        #expect(LocalPreferences.defaults.double(forKey: "agentpet.animationFPS") == 12)
        for mood in PetMood.allCases {
            #expect(controller.spriteFPS(forMood: mood) <= 2)
        }
        controller.animationFPS = 9
        #expect(controller.animationFPS == 2)
        controller.animationFPS = 0
        #expect(controller.animationFPS == 1)
    }

    @Test func statusChangesDoNotResetBlinkingOrApplyBodyTransforms() async throws {
        let saved = LocalPreferences.defaults.object(forKey: "agentpet.animationFPS")
        defer { restoreFPS(saved) }
        let controller = PetController()
        controller.animationFPS = 2
        let pet = pack([[try frame(.red), try frame(.green), try frame(.blue)]])
        let view = SpriteLayerNSView()
        defer { view.teardown() }
        view.configure(frames: pet.restingFrames, fps: controller.spriteFPS(forMood: .idle))
        let initial = try displayedFrame(view)
        try await waitForNextFrame(view, after: initial)
        let blinking = try displayedFrame(view)
        #expect(blinking != initial)
        for mood in PetMood.allCases {
            // Same call path used by the desktop pet and settings preview.
            view.configure(frames: pet.restingFrames, fps: controller.spriteFPS(forMood: mood))
            #expect(try displayedFrame(view) == blinking)
            #expect(CATransform3DIsIdentity(try #require(view.layer).transform))
            #expect(view.layer?.animationKeys()?.isEmpty ?? true)
        }
    }

    @Test func disabledAnimationAndTeardownStillStopTheIdleTimer() async throws {
        let frames = [try frame(.red), try frame(.green)]
        let view = SpriteLayerNSView()
        defer { view.teardown() }
        view.configure(frames: frames, fps: 2, animate: false)
        let frozen = try displayedFrame(view)
        try await Task.sleep(for: .milliseconds(650))
        #expect(try displayedFrame(view) == frozen)

        view.configure(frames: frames, fps: 2, animate: true)
        try await waitForNextFrame(view, after: frozen)
        view.teardown()
        let stopped = try displayedFrame(view)
        try await Task.sleep(for: .milliseconds(650))
        #expect(try displayedFrame(view) == stopped)
    }
}
