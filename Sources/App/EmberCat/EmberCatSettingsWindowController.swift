import AppKit
import SwiftUI

@MainActor
final class EmberCatSettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = EmberCatSettingsWindowController()
    private let settingsOwner = UUID()
    private let previewOwner = UUID()
    private(set) var window: NSWindow?
    private var preview: NotchFlamePreviewController?

    var hasOpenWindow: Bool {
        window != nil || preview?.window?.isVisible == true
    }

    func show() {
        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.deminiaturize(nil)
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 690),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "LuMate · 噜伴 · EmberCat 设置"
        window.identifier = NSUserInterfaceItemIdentifier("embercat-settings-window")
        window.contentMinSize = NSSize(width: 520, height: 600)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: EmberCatSettingsView(
            integration: .shared, showFlamePreview: { [weak self] in self?.showFlamePreview() }))
        window.center()
        self.window = window
        AppWindowActivation.acquire(settingsOwner)
        DispatchQueue.main.async { [weak self, weak window] in
            guard let window, self?.window === window else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    func showFlamePreview() {
        do {
            if preview == nil {
                let preview = try NotchFlamePreviewController(settings: EmberCatIntegration.shared.flameSettings)
                preview.onClose = { [weak self] in
                    guard let self else { return }
                    AppWindowActivation.release(self.previewOwner)
                }
                self.preview = preview
            }
            AppWindowActivation.acquire(previewOwner)
            preview?.showWindow(nil)
        } catch {
            let alert = NSAlert()
            alert.messageText = "无法打开火焰预览"
            alert.informativeText = "Metal 渲染器初始化失败：\(error.localizedDescription)"
            if let window { alert.beginSheetModal(for: window) }
            else { alert.runModal() }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard (notification.object as? NSWindow) === window else { return }
        window = nil
        AppWindowActivation.release(settingsOwner)
    }

    func shutdown() {
        preview?.close()
        preview = nil
        window?.close()
        window = nil
        AppWindowActivation.release(previewOwner)
        AppWindowActivation.release(settingsOwner)
    }
}
