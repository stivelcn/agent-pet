import AppKit
import SwiftUI
import Foundation
import Testing
import AgentPetCore
@testable import agentpet

/// Offscreen AppKit rendering only: no app is launched, no Keychain access or network requests.
@MainActor
@Suite(.serialized)
struct IterationViewTests {
    private func render<V: View>(_ view: V, name: String) throws -> NSSize {
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view.environment(\.locale, Locale(identifier: "zh-Hans")))
        let size = host.fittingSize
        #expect(size.width.isFinite && size.height.isFinite)
        #expect(size.width > 0 && size.height > 0)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        if let directory = ProcessInfo.processInfo.environment["AGENTPET_UI_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            let png = try #require(bitmap.representation(using: .png, properties: [:]))
            try png.write(to: url.appendingPathComponent(name + ".png"))
        }
        window.contentView = nil
        return size
    }

    @Test func collapsedAndExpandedMessageViewsRenderWithoutChangingMailbox() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("lumate-view-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        var mailbox = PetRelayMailbox()
        mailbox.pair = PetRelayPair(id: "pair", peerName: "噜噜")
        mailbox.incoming = (0..<8).map { index in
            PetRelayMessage(id: "m\(index)", clientID: "c\(index)", pairID: "pair", senderName: "噜噜",
                text: index == 0 ? "记得休息，回来给我说一声哦 😊" : "第\(index + 1)条完整消息，等你回来一起吃饭", createdAt: 1_794_000_000 + Double(index))
        }
        let file = directory.appendingPathComponent("mailbox.json")
        try JSONEncoder().encode(mailbox).write(to: file)
        let relay = PetRelayController(fileURL: file, credentials: PetRelayKeychain(endpoint: PetRelayAPI.endpoint),
                                       api: PetRelayAPI(), enabled: false, events: false)
        let collapsed = try render(PetMessageBubble(relay: relay), name: "messages-collapsed")
        let expanded = try render(PetMessageBubble(relay: relay, initiallyExpanded: true), name: "messages-expanded")
        #expect(collapsed.width == 270)
        #expect(expanded.width == 320)
        #expect(expanded.height > collapsed.height)
        #expect(expanded.height < 400)
        #expect(relay.mailbox == mailbox)
        #expect(try JSONDecoder().decode(PetRelayMailbox.self, from: Data(contentsOf: file)) == mailbox)
    }

    @Test func updateSectionRendersInTheSettingsForm() throws {
        let update = AppUpdateController(currentVersion: "0.2.1")
        let size = try render(Form { AppUpdateView(update: update) }.formStyle(.grouped).frame(width: 590, height: 360), name: "update-settings")
        #expect(size.width == 590)
        #expect(update.phase == .idle)
    }
}
