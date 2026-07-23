import AppKit
import Foundation
import SwiftUI

enum PaceSeverity: Equatable {
    case none
    case warning
    case critical

    var color: Color {
        switch self {
        case .none: return Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255) // #22c55e
        case .warning: return Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255) // #eab308
        case .critical: return Color(red: 249 / 255, green: 115 / 255, blue: 22 / 255) // #f97316
        }
    }

    var nsColor: NSColor {
        switch self {
        case .none:
            return NSColor(calibratedRed: 34 / 255, green: 197 / 255, blue: 94 / 255, alpha: 1)
        case .warning:
            return NSColor(calibratedRed: 234 / 255, green: 179 / 255, blue: 8 / 255, alpha: 1)
        case .critical:
            return NSColor(calibratedRed: 249 / 255, green: 115 / 255, blue: 22 / 255, alpha: 1)
        }
    }

    static func worst(_ a: PaceSeverity, _ b: PaceSeverity) -> PaceSeverity {
        let rank: (PaceSeverity) -> Int = {
            switch $0 {
            case .none: return 0
            case .warning: return 1
            case .critical: return 2
            }
        }
        return rank(a) >= rank(b) ? a : b
    }
}

struct PaceInfo: Equatable {
    var severity: PaceSeverity
    var projected: Int?
}

struct UsageSnapshot: Equatable {
    var autoPercent: Double
    var apiPercent: Double
    var totalPercent: Double
    var totalSpendCents: Double
    var includedSpendCents: Double
    var bonusSpendCents: Double
    var limitCents: Double
    var billingCycleStart: Date?
    var billingCycleEnd: Date?
    var fetchedAt: Date

    var autoRounded: Int { Int(autoPercent.rounded()) }
    var apiRounded: Int { Int(apiPercent.rounded()) }
    var totalRounded: Int { Int(totalPercent.rounded()) }

    var includedDollars: String { Self.dollars(includedSpendCents) }
    var bonusDollars: String { Self.dollars(bonusSpendCents) }
    var totalDollars: String { Self.dollars(totalSpendCents) }

    var daysLeft: Int? {
        guard let end = billingCycleEnd else { return nil }
        return max(0, Int(ceil(end.timeIntervalSinceNow / 86_400)))
    }

    var totalDays: Int {
        guard let start = billingCycleStart, let end = billingCycleEnd else { return 30 }
        return max(1, Int((end.timeIntervalSince(start) / 86_400).rounded()))
    }

    var dayIndex: Int? {
        guard let daysLeft else { return nil }
        return max(1, totalDays - daysLeft)
    }

    var resetLabel: String {
        guard let daysLeft else { return "?" }
        if daysLeft == 0 { return "resets today" }
        if daysLeft == 1 { return "1d left" }
        return "\(daysLeft)d left"
    }

    var resetDateLabel: String {
        guard let end = billingCycleEnd else { return "?" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: end)
    }

    var elapsedFraction: Double? {
        if let start = billingCycleStart, let end = billingCycleEnd, end > start {
            return min(1, max(0, Date().timeIntervalSince(start) / end.timeIntervalSince(start)))
        }
        if let daysLeft {
            return min(1, max(0, Double(totalDays - daysLeft) / Double(totalDays)))
        }
        return nil
    }

    var autoPace: PaceInfo { Self.paceSeverity(pct: autoPercent, elapsedFrac: elapsedFraction) }
    var apiPace: PaceInfo { Self.paceSeverity(pct: apiPercent, elapsedFrac: elapsedFraction) }
    var totalPace: PaceInfo { Self.paceSeverity(pct: totalPercent, elapsedFrac: elapsedFraction) }

    var overallSeverity: PaceSeverity {
        PaceSeverity.worst(PaceSeverity.worst(autoPace.severity, apiPace.severity), totalPace.severity)
    }

    static func dollars(_ cents: Double) -> String {
        String(format: "%.2f", cents / 100)
    }

    /// Matches extension `paceSeverity`.
    static func paceSeverity(pct: Double, elapsedFrac: Double?) -> PaceInfo {
        guard let elapsedFrac, elapsedFrac.isFinite, elapsedFrac > 0, pct.isFinite else {
            return PaceInfo(severity: .none, projected: nil)
        }
        if pct >= 100 {
            return PaceInfo(severity: .critical, projected: Int(pct.rounded()))
        }
        let projected = pct / elapsedFrac
        let rounded = Int(projected.rounded())
        if elapsedFrac < 0.05 {
            if projected > 200 { return PaceInfo(severity: .critical, projected: rounded) }
            if projected > 150 { return PaceInfo(severity: .warning, projected: rounded) }
            return PaceInfo(severity: .none, projected: rounded)
        }
        if projected > 130 { return PaceInfo(severity: .critical, projected: rounded) }
        if projected > 100 { return PaceInfo(severity: .warning, projected: rounded) }
        return PaceInfo(severity: .none, projected: rounded)
    }
}

enum UsageLoadState: Equatable {
    case idle
    case loading
    case loaded(UsageSnapshot)
    case error(String)
}
