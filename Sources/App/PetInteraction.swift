import AppKit
import Combine

/// Explicit social actions are independent of task moods and the quiet idle loop.
enum PetInteraction: String, CaseIterable, Codable, Identifiable {
    case poke, poked, hug, peek
    var id: String { rawValue }

    var label: String {
        switch self {
        case .poke: "Poke"
        case .poked: "Poked reaction"
        case .hug: "Hug"
        case .peek: "Peek"
        }
    }

    var symbol: String {
        switch self {
        case .poke: "hand.point.right.fill"
        case .poked: "sparkle"
        case .hug: "heart.fill"
        case .peek: "eye.fill"
        }
    }
}

struct PetInteractionClip {
    let frames: [NSImage]
    let frameDurations: [TimeInterval]
    var duration: TimeInterval { frameDurations.reduce(0, +) }
}

/// Optional sidecar: old/imported packs continue to work without interaction art.
enum PetInteractionLibrary {
    private struct Manifest: Decodable {
        let version: Int
        let spritesheetPath: String
        let cellWidth: Int
        let cellHeight: Int
        let clips: [String: Clip]
        struct Clip: Decodable {
            let row: Int
            let frameDurationsMS: [Double]
        }
    }

    static func load(directory: URL) -> [PetInteraction: PetInteractionClip] {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("interactions.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.version == 1,
              manifest.cellWidth > 0, manifest.cellHeight > 0,
              !manifest.spritesheetPath.isEmpty,
              manifest.spritesheetPath == (manifest.spritesheetPath as NSString).lastPathComponent,
              let image = NSImage(contentsOf: directory.appendingPathComponent(manifest.spritesheetPath))
        else { return [:] }
        var rect = CGRect(origin: .zero, size: image.size)
        guard let sheet = image.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              sheet.width % manifest.cellWidth == 0, sheet.height % manifest.cellHeight == 0
        else { return [:] }
        let columns = sheet.width / manifest.cellWidth
        let rows = sheet.height / manifest.cellHeight
        var result: [PetInteraction: PetInteractionClip] = [:]
        for (name, clip) in manifest.clips {
            guard let action = PetInteraction(rawValue: name),
                  clip.row >= 0, clip.row < rows,
                  (2...24).contains(clip.frameDurationsMS.count),
                  clip.frameDurationsMS.count <= columns,
                  clip.frameDurationsMS.allSatisfy({ $0.isFinite && (20...2_000).contains($0) }),
                  clip.frameDurationsMS.reduce(0, +) <= 4_000
            else { continue }
            let frames = clip.frameDurationsMS.indices.compactMap { column -> NSImage? in
                guard let frame = sheet.cropping(to: CGRect(
                    x: column * manifest.cellWidth, y: clip.row * manifest.cellHeight,
                    width: manifest.cellWidth, height: manifest.cellHeight
                )) else { return nil }
                return NSImage(cgImage: frame, size: NSSize(width: frame.width, height: frame.height))
            }
            guard frames.count == clip.frameDurationsMS.count else { continue }
            result[action] = PetInteractionClip(frames: frames,
                                                frameDurations: clip.frameDurationsMS.map { $0 / 1_000 })
        }
        return result
    }
}

@MainActor
final class PetInteractionPlayer: ObservableObject {
    @Published private(set) var action: PetInteraction?
    @Published private(set) var playbackID = UUID()

    @discardableResult
    func play(_ action: PetInteraction, in pack: ImagePetPack,
              animationsEnabled: Bool = true, reduceMotion: Bool = false) -> Bool {
        guard animationsEnabled, !reduceMotion, pack.interactionClips[action] != nil else {
            stop()
            return false
        }
        playbackID = UUID()
        self.action = action
        return true
    }

    func finish(_ id: UUID) {
        guard playbackID == id else { return }
        stop()
    }

    func stop() {
        guard action != nil else { return }
        action = nil
        playbackID = UUID()
    }
}
