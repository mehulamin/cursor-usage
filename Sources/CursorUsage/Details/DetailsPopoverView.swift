import SwiftUI

struct DetailsPopoverView: View {
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var settings: AppSettings

    private var fontScale: CGFloat { settings.fontSize.scale }

    var body: some View {
        VStack(alignment: .leading, spacing: MacUI.Density.gap * fontScale) {
            header
            content
            footer
        }
        .padding(MacUI.Density.dialogPad)
        .frame(width: 340)
        .font(MacUI.bodyFont(scale: fontScale))
        .foregroundStyle(MacUI.Colors.primaryText)
        // System NSPopover supplies the single Liquid Glass chrome layer.
        .background(Color.clear)
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "chart.bar.fill")
                .font(.system(size: MacUI.Density.iconSize * fontScale))
                .foregroundStyle(MacUI.Colors.secondaryText)
                .accessibilityHidden(true)
            Text("Cursor Usage")
                .font(MacUI.headlineFont(scale: fontScale * 1.08))
            Spacer(minLength: 0)
            if case .loading = viewModel.state {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: MacUI.Density.spinnerSize, height: MacUI.Density.spinnerSize)
            }
        }
        .frame(minHeight: MacUI.Density.controlHeight)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Cursor Usage")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            VStack(spacing: MacUI.Density.gap) {
                ProgressView()
                    .controlSize(.regular)
                Text("Loading usage…")
                    .foregroundStyle(MacUI.Colors.secondaryText)
            }
            .frame(maxWidth: .infinity, minHeight: 180)

        case .error(let message):
            VStack(alignment: .leading, spacing: MacUI.Density.gap) {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if message.contains("token") || message.contains("paste") {
                    Text("Open Settings to paste your WorkosCursorSessionToken, or detect it from the Cursor app.")
                        .foregroundStyle(MacUI.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Open Settings…") {
                        viewModel.openSettings()
                    }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(",", modifiers: .command)
                } else {
                    Button("Try Again") {
                        Task { await viewModel.refresh() }
                    }
                    .buttonStyle(.macPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(MacUI.Density.gap)
            .macOpaqueCard()

        case .loaded(let snap):
            VStack(alignment: .leading, spacing: MacUI.Density.gap) {
                cycleHeader(snap)
                metricRows(snap)
                spendSection(snap)
            }
            .padding(MacUI.Density.gap)
            .frame(maxWidth: .infinity, alignment: .leading)
            .macOpaqueCard()
        }
    }

    private func cycleHeader(_ snap: UsageSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text("Resets \(snap.resetDateLabel) · \(snap.resetLabel)")
                    .font(MacUI.calloutFont(scale: fontScale).weight(.medium))
            } icon: {
                Image(systemName: "calendar")
                    .font(.system(size: MacUI.Density.iconSize * 0.85 * fontScale))
            }
            .foregroundStyle(MacUI.Colors.secondaryText)

            if let day = snap.dayIndex {
                Text("Day \(day) of \(snap.totalDays)")
                    .font(MacUI.captionFont(scale: fontScale))
                    .foregroundStyle(MacUI.Colors.tertiaryText)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func metricRows(_ snap: UsageSnapshot) -> some View {
        VStack(spacing: MacUI.Density.gap) {
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
                .font(MacUI.calloutFont(scale: fontScale).weight(.semibold))
            Text("Included $\(snap.includedDollars) · Bonus $\(snap.bonusDollars) · Total $\(snap.totalDollars)")
                .font(MacUI.calloutFont(scale: fontScale))
                .foregroundStyle(MacUI.Colors.secondaryText)
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Spend this period: included \(snap.includedDollars) dollars, bonus \(snap.bonusDollars) dollars, total \(snap.totalDollars) dollars")
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Rectangle()
                .fill(MacUI.Colors.divider)
                .frame(height: 1)
            HStack(alignment: .center, spacing: MacUI.Density.gap) {
                Button {
                    viewModel.openCursorDashboard()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: MacUI.Density.iconSize * 0.85 * fontScale))
                        Text("Open online")
                    }
                }
                .buttonStyle(.macSecondary)

                Spacer(minLength: 8)

                HStack(spacing: 8) {
                    if case .loaded(let snap) = viewModel.state {
                        Text(relativeTime(snap.fetchedAt))
                            .font(MacUI.calloutFont(scale: fontScale))
                            .foregroundStyle(MacUI.Colors.tertiaryText)
                            .accessibilityLabel("Last refreshed \(relativeTime(snap.fetchedAt))")
                    }

                    Button {
                        Task { await viewModel.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: MacUI.Density.iconSize * fontScale))
                            .frame(width: MacUI.Density.controlHeight, height: MacUI.Density.controlHeight)
                    }
                    .buttonStyle(.macSecondary)
                    .disabled(isLoading)
                    .help("Refresh usage")
                    .accessibilityLabel("Refresh")
                }
            }

            Text(tokenExpirationText)
                .font(MacUI.captionFont(scale: fontScale))
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
            return MacUI.Colors.secondaryText
        }
        if TokenStore.isExpired(token) {
            return MacUI.Colors.destructive
        }
        guard let exp = TokenStore.expirationDate(ofToken: token),
              let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day
        else {
            return MacUI.Colors.secondaryText
        }
        if days < 3 {
            return MacUI.Colors.destructive
        }
        if days < 7 {
            return .yellow
        }
        return MacUI.Colors.secondaryText
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
            HStack(spacing: 8) {
                Circle()
                    .fill(pace.severity.color)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(title)
                    .font(MacUI.calloutFont(scale: fontScale).weight(.medium))
                Spacer(minLength: 0)
                Text("\(percent)%")
                    .font(MacUI.calloutFont(scale: fontScale).weight(.semibold).monospacedDigit())
                if let projected = pace.projected, pace.severity != .none {
                    Text(percent >= 100 ? "max" : "~\(projected)%")
                        .font(MacUI.captionFont(scale: fontScale).weight(.semibold).monospacedDigit())
                        .foregroundStyle(pace.severity.chipForeground)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(pace.severity.chipBackground, in: Capsule())
                }
            }
            .frame(minHeight: MacUI.Density.controlHeight * 0.75)

            MacProgressBar(value: Double(percent), tint: pace.severity.color)
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
