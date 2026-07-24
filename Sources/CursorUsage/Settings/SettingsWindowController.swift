import AppKit
import SwiftUI

/// Presents Settings in a dedicated NSWindow — more reliable than the SwiftUI
/// Settings scene alone for `LSUIElement` / accessory apps.
@MainActor
enum SettingsWindowController {
    private static var window: NSWindow?

    /// True when the Account token draft differs from the saved session token.
    static var hasUnsavedChanges = false

    private static let defaultContentSize = NSSize(width: 760, height: 680)
    private static let minimumContentSize = NSSize(width: 720, height: 600)

    private final class Window: NSWindow {
        override func cancelOperation(_ sender: Any?) {
            guard !SettingsWindowController.hasUnsavedChanges else { return }
            close()
        }
    }

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

        let window = Window(contentViewController: hosting)
        window.title = "Cursor Usage Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(Self.defaultContentSize)
        window.contentMinSize = Self.minimumContentSize
        window.isReleasedWhenClosed = false
        window.center()
        window.level = .floating
        window.titlebarAppearsTransparent = false
        window.backgroundColor = .windowBackgroundColor

        Self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static func close() {
        window?.close()
    }
}
