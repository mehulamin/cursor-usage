import SwiftUI

struct DetailsPopoverView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var settings: AppSettings

    private var fontScale: CGFloat { settings.fontSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: 16 * fontScale) {
            header
            content
            footer
        }
        .padding(16)
        .frame(width: 340)
        .background(.regularMaterial)
        .font(.system(size: 13 * fontScale))
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: "chart.bar.fill")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Cursor Usage")
                .font(.system(size: 15 * fontScale, weight: .semibold))
            Spacer()
            if case .loading = viewModel.state {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cursor Usage")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: 12) {
                ProgressView()
                Text("Loading usage…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 180)

        case .error(let message):
            VStack(alignment: .leading, spacing: 12) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if message.contains("token") || message.contains("paste") {
                    Text("Open Settings to paste your WorkosCursorSessionToken, or detect it from the Cursor app.")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings…") {
                        viewModel.openSettings()
                    }
                    .keyboardShortcut(",", modifiers: .command)
                } else {
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)

        case .loaded(let snap):
            cycleHeader(snap)
            metricRows(snap)
            spendSection(snap)
        }
    }

    private func cycleHeader(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Resets \(snap.resetDateLabel) · \(snap.resetLabel)")
                    .font(.system(size: 12 * fontScale, weight: .medium))
            } icon: {
                Image(systemName: "calendar")
            }
            .foregroundStyle(.secondary)

            if let day = snap.dayIndex {
                Text("Day \(day) of \(snap.totalDays)")
                    .font(.system(size: 11 * fontScale))
                    .foregroundStyle(.tertiary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metricRows(_ snap: UsageSnapshot) -> some View {
        VStack(spacing: 12) {
            MetricRow(
                title: "Auto + Composer",
                percent: snap.autoRounded,
                pace: snap.autoPace,
                fontScale: fontScale
            )
            MetricRow(
                title: "API (named models)",
                percent: snap.apiRounded,
                pace: snap.apiPace,
                fontScale: fontScale
            )
            MetricRow(
                title: "Total used",
                percent: snap.totalRounded,
                pace: snap.totalPace,
                fontScale: fontScale
            )
        }
    }

    private func spendSection(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Spend this period")
                .font(.system(size: 12 * fontScale, weight: .semibold))
            Text("Included $\(snap.includedDollars) · Bonus $\(snap.bonusDollars) · Total $\(snap.totalDollars)")
                .font(.system(size: 12 * fontScale))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spend this period: included \(snap.includedDollars) dollars, bonus \(snap.bonusDollars) dollars, total \(snap.totalDollars) dollars")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            HStack(alignment: .center, spacing: 12) {
                Button {
                    viewModel.openCursorDashboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                        Text("Open online")
                    }
                }
                .buttonStyle(.link)

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    if case .loaded(let snap) = viewModel.state {
                        Text(relativeTime(snap.fetchedAt))
                            .font(.system(size: 12 * fontScale))
                            .foregroundStyle(.tertiary)
                            .accessibilityLabel("Last refreshed \(relativeTime(snap.fetchedAt))")
                    }

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.link)
                    .disabled(isLoading)
                    .help("Refresh usage")
                    .accessibilityLabel("Refresh")
                }
            }

            Text(tokenExpirationText)
                .font(.system(size: 11 * fontScale))
                .foregroundStyle(tokenExpirationColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel(tokenExpirationText)
        }
    }

    private var isLoading: Bool {
        if case .loading = viewModel.state { return true }
        return false
    }

    private var tokenExpirationText: String {
        TokenStore.expirationSummary(ofToken: settings.sessionToken)
    }

    /// Red when expired or fewer than 3 days left; yellow when fewer than 7 days left.
    private var tokenExpirationColor: Color {
        let token = settings.sessionToken
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .secondary
        }
        if TokenStore.isExpired(token) {
            return .red
        }
        guard let exp = TokenStore.expirationDate(ofToken: token),
              let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day
        else {
            return .secondary
        }
        if days < 3 {
            return .red
        }
        if days < 7 {
            return .yellow
        }
        return .secondary
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

private struct MetricRow: View {
    let title: String
    let percent: Int
    let pace: PaceInfo
    let fontScale: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Circle()
                    .fill(pace.severity.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 12 * fontScale, weight: .medium))
                Spacer()
                Text("\(percent)%")
                    .font(.system(size: 12 * fontScale, weight: .semibold).monospacedDigit())
                if let projected = pace.projected, pace.severity != .none {
                    Text(percent >= 100 ? "max" : "~\(projected)%")
                        .font(.system(size: 11 * fontScale, weight: .semibold).monospacedDigit())
                        .foregroundStyle(pace.severity.chipForeground)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(pace.severity.chipBackground, in: Capsule())
                }
            }
            ProgressView(value: min(Double(percent), 100), total: 100)
                .tint(pace.severity.color)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var text = "\(title) \(percent) percent"
        if let projected = pace.projected, pace.severity != .none {
            text += percent >= 100 ? ", at maximum" : ", projected \(projected) percent"
        }
        return text
    }
}
