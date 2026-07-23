import AppKit
import Combine
import SwiftUI

/// Owns the menu-bar status item, dropdown menu, and Details popover.
/// Left-click → Details popover. Right-click (or Control-click) → menu.
@MainActor
final class StatusItemController: NSObject, ObservableObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var statusMenu: NSMenu?
    private var popover: NSPopover?
    private var viewModel: UsageViewModel { .shared }
    private var settings: AppSettings { .shared }
    private var cancellables = Set<AnyCancellable>()
    private var appearanceObservation: NSKeyValueObservation?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?

    private override init() {
        super.init()
    }

    func install() {
        guard statusItem == nil else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }
        statusItem = item

        button.toolTip = "Cursor Usage"
        button.setAccessibilityTitle("Cursor Usage")
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        let menu = NSMenu(title: "Cursor Usage")
        menu.autoenablesItems = false
        menu.delegate = self

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cursor Usage", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        menu.addItem(quit)

        statusMenu = menu
        // Do not assign item.menu permanently — that would make left-click open the menu.

        // Menu-bar contrast follows the wallpaper behind the item, not the app theme.
        appearanceObservation = button.observe(\.effectiveAppearance, options: [.new]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.updateTitle()
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appearanceChanged),
            name: NSNotification.Name("NSApplicationDidChangeEffectiveAppearanceNotification"),
            object: nil
        )

        viewModel.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateTitle()
                }
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.updateTitle()
                }
            }
            .store(in: &cancellables)

        updateTitle()
    }

    @objc private func appearanceChanged() {
        updateTitle()
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        guard let event = NSApp.currentEvent else {
            showDetails()
            return
        }

        let isRightClick = event.type == .rightMouseUp
        let isControlClick = event.modifierFlags.contains(.control)
        if isRightClick || isControlClick {
            showStatusMenu()
        } else {
            showDetails()
        }
    }

    private func showStatusMenu() {
        guard let item = statusItem, let menu = statusMenu, let button = item.button else { return }
        closePopover()
        // Temporarily attach the menu so the status item can pop it up correctly,
        // then clear it in menuDidClose so the next left-click stays on Details.
        item.menu = menu
        button.performClick(nil)
    }

    func updateTitle() {
        guard let button = statusItem?.button else { return }
        let title = viewModel.statusTitle()
        let font = NSFont.menuBarFont(ofSize: settings.fontSize.menuBarPointSize)
        let color = menuBarTitleColor(for: button)

        button.contentTintColor = nil
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: color
            ]
        )
        button.toolTip = "Cursor Usage — click for details, right-click for menu"
        button.appearsDisabled = false
        button.isEnabled = true
    }

    /// Readable on both light and dark menu-bar regions (wallpaper-driven).
    private func menuBarTitleColor(for button: NSStatusBarButton) -> NSColor {
        let dark = isDarkAppearance(button.effectiveAppearance)
        switch viewModel.statusSeverity() {
        case .warning:
            return .systemYellow
        case .critical:
            return .systemOrange
        case .error:
            return .systemRed
        case .normal:
            return dark ? .white : .black
        }
    }

    private func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    @objc func showDetails() {
        guard let button = statusItem?.button else { return }

        if let popover, popover.isShown {
            closePopover()
            return
        }

        statusItem?.menu?.cancelTracking()

        // Accessory (LSUIElement) apps must activate so the popover can become key;
        // otherwise transient dismiss-on-outside-click never fires.
        NSApp.activate(ignoringOtherApps: true)

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        // Content sizes itself; glass chrome lives in DetailsPopoverView.
        popover.contentSize = NSSize(width: 340, height: 1)

        let root = DetailsPopoverView()
            .environmentObject(viewModel)
            .environmentObject(settings)

        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        popover.contentViewController = hosting
        self.popover = popover

        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Become key on the next turn so the popover window exists.
        DispatchQueue.main.async {
            if let window = hosting.view.window {
                window.isOpaque = false
                window.backgroundColor = .clear
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(hosting.view)
            }
            // Delay monitors so the opening click doesn't immediately dismiss.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.installOutsideClickMonitors()
            }
        }
    }

    @objc func openSettings() {
        closePopover()
        viewModel.openSettings()
    }

    @objc func quitApp() {
        viewModel.quit()
    }

    func closePopover() {
        removeOutsideClickMonitors()
        popover?.performClose(nil)
        popover = nil
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()

        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.handlePotentialOutsideClick(event)
            return event
        }

        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.closePopover()
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor {
            NSEvent.removeMonitor(localMouseMonitor)
            self.localMouseMonitor = nil
        }
        if let globalMouseMonitor {
            NSEvent.removeMonitor(globalMouseMonitor)
            self.globalMouseMonitor = nil
        }
    }

    private func handlePotentialOutsideClick(_ event: NSEvent) {
        guard let popover, popover.isShown else { return }

        // Clicks on the status item are handled by the toggle in showDetails.
        if isClickOnStatusItem(event) {
            return
        }

        if let popoverWindow = popover.contentViewController?.view.window,
           event.window == popoverWindow {
            return
        }

        closePopover()
    }

    private func isClickOnStatusItem(_ event: NSEvent) -> Bool {
        guard let button = statusItem?.button, let buttonWindow = button.window else {
            return false
        }
        guard event.window == buttonWindow else { return false }
        let point = button.convert(event.locationInWindow, from: nil)
        return button.bounds.contains(point)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // Detach so left-click does not open the menu next time.
        statusItem?.menu = nil
    }
}

extension StatusItemController: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        removeOutsideClickMonitors()
        popover = nil
    }
}
