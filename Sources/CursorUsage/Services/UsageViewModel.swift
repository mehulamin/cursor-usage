import AppKit
import Combine
import Foundation
import SwiftUI

enum MenuBarSeverity {
    case normal
    case warning
    case critical
    case error
}

@MainActor
final class UsageViewModel: ObservableObject {
    static let shared = UsageViewModel()

    @Published private(set) var state: UsageLoadState = .idle

    let settings = AppSettings.shared
    private let client = UsageClient()
    private var refreshTask: Task<Void, Never>?
    private var systemTriggerRefreshTask: Task<Void, Never>?
    private var timerCancellable: AnyCancellable?
    private var settingsCancellables = Set<AnyCancellable>()
    private var lastScheduledMinutes: Int?
    private var didRefreshOnLaunch = false
    private var workspaceObservers: [NSObjectProtocol] = []
    private var distributedObservers: [NSObjectProtocol] = []
    private static let systemTriggerRefreshDelay: Duration = .seconds(3)

    var snapshot: UsageSnapshot? {
        if case .loaded(let s) = state { return s }
        return nil
    }

    private init() {
        settings.$refreshIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reschedule()
            }
            .store(in: &settingsCancellables)

        Publishers.Merge3(
            settings.$refreshOnWake.map { _ in () },
            settings.$refreshOnScreenUnlock.map { _ in () },
            settings.$refreshOnSessionActive.map { _ in () }
        )
        .debounce(for: .milliseconds(50), scheduler: RunLoop.main)
        .sink { [weak self] in
            self?.rebuildSystemTriggers()
        }
        .store(in: &settingsCancellables)
    }

    func start() {
        rebuildSystemTriggers()
        if settings.refreshOnLaunch, !didRefreshOnLaunch {
            didRefreshOnLaunch = true
            scheduleRefreshFromSystemTrigger()
        }
        reschedule()
    }

    func reschedule() {
        let minutes = max(5, min(60, settings.refreshIntervalMinutes))
        if lastScheduledMinutes == minutes, timerCancellable != nil { return }
        lastScheduledMinutes = minutes
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: TimeInterval(minutes * 60), on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task { @MainActor in
                    await self?.refresh()
                }
            }
    }

    func rebuildSystemTriggers() {
        removeSystemObservers()

        let workspace = NSWorkspace.shared.notificationCenter
        if settings.refreshOnWake {
            workspaceObservers.append(
                workspace.addObserver(
                    forName: NSWorkspace.didWakeNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleRefreshFromSystemTrigger()
                    }
                }
            )
        }
        if settings.refreshOnSessionActive {
            workspaceObservers.append(
                workspace.addObserver(
                    forName: NSWorkspace.sessionDidBecomeActiveNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleRefreshFromSystemTrigger()
                    }
                }
            )
        }
        if settings.refreshOnScreenUnlock {
            distributedObservers.append(
                DistributedNotificationCenter.default().addObserver(
                    forName: Notification.Name("com.apple.screenIsUnlocked"),
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in
                        self?.scheduleRefreshFromSystemTrigger()
                    }
                }
            )
        }
    }

    /// System triggers (launch, wake, unlock, session active) wait briefly so the
    /// network stack can settle before fetching usage.
    private func scheduleRefreshFromSystemTrigger() {
        systemTriggerRefreshTask?.cancel()
        systemTriggerRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: Self.systemTriggerRefreshDelay)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    private func removeSystemObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        for token in workspaceObservers {
            workspace.removeObserver(token)
        }
        workspaceObservers.removeAll()
        let distributed = DistributedNotificationCenter.default()
        for token in distributedObservers {
            distributed.removeObserver(token)
        }
        distributedObservers.removeAll()
    }

    func refresh() async {
        refreshTask?.cancel()
        let task = Task { @MainActor in
            await self.performRefresh()
        }
        refreshTask = task
        await task.value
    }

    private func performRefresh() async {
        state = .loading

        let manual = settings.sessionToken
        let token = await TokenStore.resolveToken(manual: manual)
        guard let token else {
            state = .error(UsageClientError.noToken.localizedDescription)
            return
        }

        if manual.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            settings.sessionToken = token
        } else {
            let normalized = TokenStore.normalizeToken(manual)
            if normalized != settings.sessionToken {
                settings.sessionToken = normalized
            }
        }

        do {
            let snapshot = try await client.fetchUsage(token: token)
            guard !Task.isCancelled else { return }
            state = .loaded(snapshot)
        } catch is CancellationError {
            // ignore
        } catch {
            guard !Task.isCancelled else { return }
            state = .error(error.localizedDescription)
        }
    }

    func detectTokenFromCursor() {
        Task {
            if let token = await TokenStore.autoDetectToken() {
                settings.sessionToken = token
                await refresh()
            }
        }
    }

    func clearToken() {
        settings.sessionToken = ""
    }

    func statusTitle() -> String {
        switch state {
        case .idle, .loading:
            return "…"
        case .error(let message):
            if message.localizedCaseInsensitiveContains("token") || message.localizedCaseInsensitiveContains("paste") {
                return "Set Token"
            }
            return "Error"
        case .loaded(let snap):
            let template = settings.menuBarTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return MenuBarTemplate.render(
                template.isEmpty ? MenuBarTemplate.defaultTemplate : template,
                snapshot: snap
            )
        }
    }

    func statusSeverity() -> MenuBarSeverity {
        switch state {
        case .loaded(let snap):
            // Color from estimated end-of-cycle Total only (not Auto/API).
            switch snap.totalPace.severity {
            case .none: return .normal
            case .warning: return .warning
            case .critical: return .critical
            }
        case .error:
            return .error
        default:
            return .normal
        }
    }

    func openSettings() {
        SettingsWindowController.show()
    }

    func openCursorDashboard() {
        if let url = URL(string: "https://cursor.com/settings") {
            NSWorkspace.shared.open(url)
        }
    }

    func quit() {
        NSApp.terminate(nil)
    }
}
