import AppKit
import SwiftUI

/// Settings and statistics share the app's Dock/keyboard activation policy.
/// Closing either window must not deactivate the other one.
@MainActor
enum AppWindowActivation {
    private static var owners: Set<UUID> = []
    static func acquire(_ owner: UUID) {
        owners.insert(owner)
        NSApp.setActivationPolicy(.regular)
    }
    static func release(_ owner: UUID) {
        owners.remove(owner)
        if owners.isEmpty { NSApp.setActivationPolicy(.accessory) }
    }
}

@MainActor
final class UsageHistoryWindowController: NSObject, NSWindowDelegate {
    static let shared = UsageHistoryWindowController()
    private let activationOwner = UUID()
    private let store: ProjectUsageStore
    private(set) var window: NSWindow?

    init(store: ProjectUsageStore = .shared) {
        self.store = store
        super.init()
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        AppWindowActivation.acquire(activationOwner)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 940, height: 780),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = NSLocalizedString("token usage statistics", comment: "statistics window")
        window.identifier = NSUserInterfaceItemIdentifier("usage-history-window")
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: UsageHistoryView(store: store))
        window.center()
        self.window = window
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        AppWindowActivation.release(activationOwner)
    }
}
