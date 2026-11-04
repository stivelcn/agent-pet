import AppKit
import Foundation
import Testing
import AgentPetCore
@testable import agentpet

@MainActor
@Suite(.serialized)
struct LocalPetRegressionTests {
    private func withPacks(_ test: (ImagePetStore) async throws -> Void) async throws {
        // scripts/test.sh supplies a disposable data directory, never the user's pet library.
        let root = URL(fileURLWithPath: AgentPetPaths.baseDir).appendingPathComponent("pets")
        #expect(AgentPetPaths.baseDir.contains(".test-state."))
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let folders = ["fixture-one", "fixture-two"].map { root.appendingPathComponent($0) }
        defer {
            for folder in folders { try? FileManager.default.removeItem(at: folder) }
            ImagePetStore.shared.reload()
        }
        let context = try #require(CGContext(data: nil, width: 32, height: 32,
            bitsPerComponent: 8, bytesPerRow: 128, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 1, green: 0.5, blue: 0, alpha: 1))
        context.fill(CGRect(x: 6, y: 6, width: 20, height: 20))
        let bitmap = NSBitmapImageRep(cgImage: try #require(context.makeImage()))
        let png = try #require(bitmap.representation(using: .png, properties: [:]))
        for folder in folders {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let manifest = ["id": folder.lastPathComponent, "displayName": "测试宠物", "spritesheetPath": "sheet.png"]
            try JSONSerialization.data(withJSONObject: manifest).write(to: folder.appendingPathComponent("pet.json"))
            try png.write(to: folder.appendingPathComponent("sheet.png"))
        }
        ImagePetStore.shared.reload()
        try await test(ImagePetStore.shared)
    }

    @Test func importedImageDecodesAndMissingResourceHasVisibleError() async throws {
        try await withPacks { store in
            let pack = try #require(store.pack(id: "fixture-one"))
            #expect(pack.clipCount == 1)
            #expect(pack.clip(0).count == 1)
            #expect(pack.clip(0)[0].size.width > 0)
            try FileManager.default.removeItem(at: pack.directory.appendingPathComponent("sheet.png"))
            store.reload()
            #expect(store.pack(id: "fixture-one") == nil)
            #expect(store.loadingMessage(for: "fixture-one").contains("加载失败"))
        }
    }

    @Test func changingSelectedPetUpdatesExistingWindowWithoutAgentEvent() async throws {
        _ = NSApplication.shared
        let windows = PetWindowController.shared
        windows.isVisible = false
        let pet = PetController.shared
        let original = pet.selectedPetID
        let split = pet.splitPet
        defer {
            pet.selectedPetID = original
            pet.splitPet = split
            windows.sync(specs: []) { _ in fatalError("No specs") }
        }
        try await withPacks { _ in
            pet.splitPet = false
            pet.selectedPetID = "fixture-one"
            pet.start()
            for _ in 0..<100 where windows.displayedPetID(forKey: "default") != "fixture-one" {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(windows.displayedPetID(forKey: "default") == "fixture-one")
            pet.selectedPetID = "fixture-two"
            for _ in 0..<100 where windows.displayedPetID(forKey: "default") != "fixture-two" {
                try await Task.sleep(for: .milliseconds(10))
            }
            #expect(windows.displayedPetID(forKey: "default") == "fixture-two")
        }
    }

    @Test func defaultLanguageIsSimplifiedChineseAndConnectionRequiresRealEvent() {
        #expect(AppLanguage.shared.lang == .zh)
        let settings = SettingsModel()
        #expect(settings.lastEvents.isEmpty)
        #expect(!settings.connectionStatus(.codex).contains("已收到客户端事件"))
        settings.recordActivity(.codex)
        #expect(settings.connectionStatus(.codex).contains("已收到客户端事件"))
    }

    @Test func allBaseKeysHaveSimplifiedChineseTranslations() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let en = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Localizations/en.lproj/Localizable.strings")) as? [String: String])
        let zh = try #require(NSDictionary(contentsOf: root.appendingPathComponent("Localizations/zh-Hans.lproj/Localizable.strings")) as? [String: String])
        #expect(Set(en.keys).subtracting(zh.keys).isEmpty)
        for key in ["LuMate", "Pet display", "Configured projects", "Get", "Name", "Save", "Agents",
                    "All", "Characters", "Creatures", "Objects", "Search pets", "Search your pets",
                    "State dot", "Separator", "Sep", "State", "community", "Registered",
                    "Show pet", "Show count on menu bar", "Show chat on menu bar",
                    "Show bubble on menu bar", "Settings", "Quit"] {
            #expect(zh[key] != nil)
            #expect(zh[key] != key)
        }
    }
}
