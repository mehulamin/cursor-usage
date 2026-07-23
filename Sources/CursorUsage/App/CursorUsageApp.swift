import AppKit
import SwiftUI

@main
struct CursorUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings scene kept for ⌘, system wiring; primary UI is SettingsWindowController.
        Settings {
            SettingsView()
                .environmentObject(UsageViewModel.shared)
                .environmentObject(AppSettings.shared)
                .environmentObject(LaunchAtLogin.shared)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Prevent duplicate menu-bar items when /Applications and dist/ both launch.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { $0 != NSRunningApplication.current }
        if !others.isEmpty {
            others.first?.activate(options: [.activateIgnoringOtherApps])
            NSApp.terminate(nil)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        StatusItemController.shared.install()
        UsageViewModel.shared.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            UsageViewModel.shared.openSettings()
        }
        return true
    }
}
