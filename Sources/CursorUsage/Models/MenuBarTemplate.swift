import Foundation

enum MenuBarTemplate {
    /// Matches the previous hardcoded menu-bar format.
    static let defaultTemplate = "{total_usage}% · {days_left}d"

    struct Tag: Identifiable, Hashable {
        let name: String
        let description: String

        var id: String { name }
        var token: String { "{\(name)}" }
        /// Legacy angle-bracket form kept for migration / render compatibility.
        var legacyToken: String { "<\(name)>" }
    }

    static let tags: [Tag] = [
        Tag(name: "total_usage", description: "Total usage percent"),
        Tag(name: "auto_usage", description: "Auto + Composer percent"),
        Tag(name: "api_usage", description: "API (named models) percent"),
        Tag(name: "days_left", description: "Days left in billing cycle"),
        Tag(name: "day", description: "Current day index in cycle"),
        Tag(name: "total_days", description: "Length of billing cycle in days"),
        Tag(name: "reset", description: "Reset label (e.g. 11d left)"),
        Tag(name: "reset_date", description: "Reset date (e.g. Jul 31)"),
        Tag(name: "spend", description: "Total spend in dollars"),
        Tag(name: "included", description: "Included spend in dollars"),
        Tag(name: "bonus", description: "Bonus spend in dollars"),
        Tag(name: "projected", description: "Projected total percent at cycle end"),
        Tag(name: "auto_projected", description: "Projected Auto percent"),
        Tag(name: "api_projected", description: "Projected API percent"),
    ]

    static func render(_ template: String, snapshot: UsageSnapshot) -> String {
        let values = values(for: snapshot)
        var result = template
        for tag in tags {
            guard let value = values[tag.name] else { continue }
            result = result.replacingOccurrences(of: tag.token, with: value)
            result = result.replacingOccurrences(of: tag.legacyToken, with: value)
        }
        return result
    }

    static func preview(_ template: String, snapshot: UsageSnapshot?) -> String {
        guard let snapshot else {
            return render(template.isEmpty ? defaultTemplate : template, snapshot: .previewSample)
        }
        return render(template.isEmpty ? defaultTemplate : template, snapshot: snapshot)
    }

    /// Rewrites legacy `<tag>` tokens to `{tag}` so saved formats stay editable.
    static func migrateLegacySyntax(_ template: String) -> String {
        var result = template
        for tag in tags {
            result = result.replacingOccurrences(of: tag.legacyToken, with: tag.token)
        }
        return result
    }

    private static func values(for snap: UsageSnapshot) -> [String: String] {
        [
            "total_usage": "\(snap.totalRounded)",
            "auto_usage": "\(snap.autoRounded)",
            "api_usage": "\(snap.apiRounded)",
            "days_left": snap.daysLeft.map(String.init) ?? "?",
            "day": snap.dayIndex.map(String.init) ?? "?",
            "total_days": "\(snap.totalDays)",
            "reset": snap.resetLabel,
            "reset_date": snap.resetDateLabel,
            "spend": snap.totalDollars,
            "included": snap.includedDollars,
            "bonus": snap.bonusDollars,
            "projected": snap.totalPace.projected.map(String.init) ?? "?",
            "auto_projected": snap.autoPace.projected.map(String.init) ?? "?",
            "api_projected": snap.apiPace.projected.map(String.init) ?? "?",
        ]
    }
}

extension UsageSnapshot {
    /// Synthetic values for settings preview when usage has not loaded yet.
    static var previewSample: UsageSnapshot {
        let now = Date()
        return UsageSnapshot(
            autoPercent: 42,
            apiPercent: 18,
            totalPercent: 80,
            totalSpendCents: 1245,
            includedSpendCents: 1000,
            bonusSpendCents: 245,
            limitCents: 2000,
            billingCycleStart: Calendar.current.date(byAdding: .day, value: -19, to: now),
            billingCycleEnd: Calendar.current.date(byAdding: .day, value: 11, to: now),
            fetchedAt: now
        )
    }
}
