import AppKit
import SwiftUI

/// Presents Settings in a dedicated NSWindow — more reliable than the SwiftUI
/// Settings scene alone for `LSUIElement` / accessory apps.
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    private static let defaultContentSize = NSSize(width: 760, height: 680)
    private static let minimumContentSize = NSSize(width: 720, height: 600)

    static func show() {
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        if let window {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let root = SettingsView()
            .environmentObject(UsageViewModel.shared)
            .environmentObject(AppSettings.shared)
            .environmentObject(LaunchAtLogin.shared)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.minSize]

        let window = NSWindow(contentViewController: hosting)
        window.title = "Cursor Usage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.defaultContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating

        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}
