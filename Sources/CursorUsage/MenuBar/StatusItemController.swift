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

        let details = NSMenuItem(title: "Details", action: #selector(showDetails), keyEquivalent: "")
        details.target = self
        details.isEnabled = true
        menu.addItem(details)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refreshUsage), keyEquivalent: "r")
        refresh.target = self
        refresh.isEnabled = true
        menu.addItem(refresh)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        settingsItem.isEnabled = true
        menu.addItem(settingsItem)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Cursor Usage", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        quit.isEnabled = true
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
            popover.performClose(nil)
            return
        }

        statusItem?.menu?.cancelTracking()

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 360, height: 440)

        let root = DetailsPopoverView()
            .environmentObject(viewModel)
            .environmentObject(settings)

        popover.contentViewController = NSHostingController(rootView: root)
        self.popover = popover

        DispatchQueue.main.async {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc func refreshUsage() {
        Task { await viewModel.refresh() }
    }

    @objc func openSettings() {
        closePopover()
        viewModel.openSettings()
    }

    @objc func quitApp() {
        viewModel.quit()
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuDidClose(_ menu: NSMenu) {
        // Detach so left-click does not open the menu next time.
        statusItem?.menu = nil
    }
}
