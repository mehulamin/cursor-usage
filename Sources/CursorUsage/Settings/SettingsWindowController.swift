import AppKit
import SwiftUI

/// Presents Settings in a dedicated NSWindow — more reliable than the SwiftUI
/// Settings scene alone for `LSUIElement` / accessory apps.
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    static func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(UsageViewModel.shared)
            .environmentObject(AppSettings.shared)

        let hosting = NSHostingController(rootView: root)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Cursor Usage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 480))
        window.minSize = NSSize(width: 640, height: 420)
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        // Let SwiftUI drive the content size within min bounds.
        window.contentView?.layoutSubtreeIfNeeded()

        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
