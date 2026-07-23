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
    private var timerCancellable: AnyCancellable?
    private var settingsCancellable: AnyCancellable?
    private var lastScheduledMinutes: Int?

    var snapshot: UsageSnapshot? {
        if case .loaded(let s) = state { return s }
        return nil
    }

    private init() {
        settingsCancellable = settings.$refreshIntervalMinutes
            .removeDuplicates()
            .sink { [weak self] _ in
                self?.reschedule()
            }
    }

    func start() {
        Task { await refresh() }
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
                return "set token"
            }
            return "error"
        case .loaded(let snap):
            // Compact menu bar: "80% · 11d"
            let daysBit: String
            if let days = snap.daysLeft {
                daysBit = "\(days)d"
            } else {
                daysBit = "?d"
            }
            return "\(snap.totalRounded)% · \(daysBit)"
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
