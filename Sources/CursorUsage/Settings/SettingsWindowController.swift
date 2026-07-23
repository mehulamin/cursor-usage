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
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 560))
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating

        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
