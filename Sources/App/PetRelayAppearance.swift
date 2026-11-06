import AppKit
import ImageIO
import SwiftUI
import AgentPetCore

/// Only a selected appearance and a small portrait leave the device. Never the pet archive.
@MainActor
enum PetRelayAppearance {
    private static var builtinPacks: [String: ImagePetPack] = [:]
    private static let portraits = NSCache<NSString, NSImage>()

    static func current() -> PetRelayPetProfile? {
        let store = ImagePetStore.shared
        guard let id = PetController.shared.selectedPetID, let pack = store.pack(id: id) else { return nil }
        let name = String(store.displayName(for: id).unicodeScalars.filter {
            !CharacterSet.controlCharacters.contains($0) && $0.value != 0x2028 && $0.value != 0x2029
        }.map(String.init).joined().prefix(20))
        let builtin = ImagePetStore.builtinDirectory.appendingPathComponent(id).resolvingSymlinksInPath()
        let builtinID = ["lulu", "lumei"].contains(id) && pack.directory.resolvingSymlinksInPath().path == builtin.path ? id : nil
        return PetRelayPetProfile(name: name.isEmpty ? "Pet friend" : name, builtinID: builtinID,
                                  thumbnailPNG: builtinID == nil ? thumbnail(pack.restingFrames.first) : nil)
    }

    static func thumbnail(_ frame: NSImage?) -> String? {
        guard let frame, let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 96, pixelsHigh: 104,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        context.cgContext.clear(CGRect(x: 0, y: 0, width: 96, height: 104))
        let ratio = min(96 / max(frame.size.width, 1), 104 / max(frame.size.height, 1))
        let size = NSSize(width: frame.size.width * ratio, height: frame.size.height * ratio)
        frame.draw(in: NSRect(x: (96 - size.width) / 2, y: (104 - size.height) / 2,
                              width: size.width, height: size.height))
        NSGraphicsContext.restoreGraphicsState()
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count <= 32_768 else { return nil }
        return data.base64EncodedString()
    }

    static func pack(for profile: PetRelayPetProfile?) -> ImagePetPack? {
        guard let id = profile?.builtinID, ["lulu", "lumei"].contains(id) else { return nil }
        if let cached = builtinPacks[id] { return cached }
        let pack = SpriteSlicer.loadPack(directory: ImagePetStore.builtinDirectory.appendingPathComponent(id))
        builtinPacks[id] = pack
        return pack
    }

    static func portrait(for profile: PetRelayPetProfile?) -> NSImage? {
        guard let encoded = profile?.thumbnailPNG, encoded.utf8.count <= 43_692 else { return nil }
        if let cached = portraits.object(forKey: encoded as NSString) { return cached }
        guard let data = Data(base64Encoded: encoded), data.count <= 32_768,
              data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              let width = props[kCGImagePropertyPixelWidth as String] as? Int,
              let height = props[kCGImagePropertyPixelHeight as String] as? Int,
              (1...128).contains(width), (1...128).contains(height),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 128
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        portraits.countLimit = 32
        portraits.setObject(image, forKey: encoded as NSString)
        return image
    }
}

struct PetRelayAvatar: View {
    var profile: PetRelayPetProfile?
    var size: CGFloat = 64
    var body: some View {
        Group {
            if let pack = PetRelayAppearance.pack(for: profile), let image = pack.restingFrames.first {
                Image(nsImage: image).resizable().scaledToFit()
            } else if let image = PetRelayAppearance.portrait(for: profile) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "pawprint.fill").resizable().scaledToFit().padding(size * 0.2).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(profile?.name ?? NSLocalizedString("Pet appearance unavailable", comment: "relay"))
    }
}

extension PetRelayMessage {
    var displayContent: String {
        guard let interaction else { return content }
        return interaction.symbol + " " + NSLocalizedString("Pet visit: " + interaction.rawValue, comment: "relay visit")
    }
}
