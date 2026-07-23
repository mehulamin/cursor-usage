import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case refresh
    case account
    case backup
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .refresh: return "Refresh"
        case .account: return "Account"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .refresh: return "arrow.clockwise"
        case .account: return "key.fill"
        case .backup: return "square.and.arrow.up.on.square"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: UsageViewModel
    @EnvironmentObject private var launchAtLogin: LaunchAtLogin
    @State private var selectedPage: SettingsPage? = .general
    @State private var tokenDraft: String = ""
    @State private var showToken = false
    @State private var detectMessage: String?
    @State private var includeTokenInExport = true
    @State private var transferMessage: String?
    @State private var transferIsError = false
    @State private var showingTokenHelp = false
    @State private var showingDetectToken = false
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(SettingsPage.allCases, selection: $selectedPage) { page in
                Label(page.title, systemImage: page.systemImage)
                    .tag(page)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 240)
            .listStyle(.sidebar)
        } detail: {
            Group {
                switch selectedPage ?? .general {
                case .general:
                    generalPage
                case .refresh:
                    refreshPage
                case .account:
                    accountPage
                case .backup:
                    backupPage
                case .about:
                    aboutPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .navigationTitle((selectedPage ?? .general).title)
        }
        .navigationSplitViewStyle(.balanced)
        .font(MacUI.bodyFont(scale: settings.fontSize.scale))
        .tint(MacUI.Colors.accent)
        .frame(minWidth: 720, idealWidth: 760, maxWidth: .infinity,
               minHeight: 600, idealHeight: 680, maxHeight: .infinity)
        .onAppear {
            tokenDraft = settings.sessionToken
            launchAtLogin.refresh()
            if selectedPage == nil {
                selectedPage = .general
            }
        }
        .onChange(of: settings.sessionToken) { _, newValue in
            if tokenDraft != newValue {
                tokenDraft = newValue
            }
        }
        .sheet(isPresented: $showingTokenHelp) {
            TokenHelpSheet()
        }
        .sheet(isPresented: $showingDetectToken) {
            DetectTokenSheet(
                savedToken: settings.sessionToken,
                draftToken: tokenDraft
            ) { detected in
                tokenDraft = detected
                detectMessage = "Detected token filled in. Click Save Token to keep it."
            }
        }
    }

    // MARK: - Pages

    private var generalPage: some View {
        Form {
            Section {
                Toggle(
                    "Start at Login",
                    isOn: Binding(
                        get: { launchAtLogin.isEnabled },
                        set: { launchAtLogin.setEnabled($0) }
                    )
                )
                .accessibilityLabel("Start at Login")

                if launchAtLogin.requiresApproval {
                    HStack(alignment: .firstTextBaseline) {
                        Text("Approval needed in System Settings.")
                            .foregroundStyle(.orange)
                            .font(.callout)
                        Spacer()
                        Button("Open Login Items…") {
                            launchAtLogin.openLoginItemsSettings()
                        }
                        .buttonStyle(.macSecondary)
                    }
                }

                if let lastError = launchAtLogin.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Open Cursor Usage automatically when you log in to this Mac.")
            }

            Section("Appearance") {
                Picker("Font Size", selection: $settings.fontSize) {
                    ForEach(FontSizeOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Font size")
            }

            Section {
                TextField("Format", text: $settings.menuBarTemplate)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .accessibilityLabel("Menu bar format")

                LabeledContent("Preview") {
                    Text(MenuBarTemplate.preview(settings.menuBarTemplate, snapshot: viewModel.snapshot))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Button("Reset to Default") {
                    settings.menuBarTemplate = MenuBarTemplate.defaultTemplate
                }
                .buttonStyle(.macSecondary)
                .disabled(settings.menuBarTemplate == MenuBarTemplate.defaultTemplate)

                Text(menuBarTemplateFooter)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } header: {
                Text("Menu Bar")
            }
        }
        .formStyle(.grouped)
        .macDialogPadding()
        .onAppear {
            launchAtLogin.refresh()
        }
    }

    private var refreshPage: some View {
        Form {
            Section {
                Stepper(value: $settings.refreshIntervalMinutes, in: 5...60, step: 5) {
                    Text("Every \(settings.refreshIntervalMinutes) minutes")
                }
                .onChange(of: settings.refreshIntervalMinutes) { _, _ in
                    viewModel.reschedule()
                }
            } header: {
                Text("Schedule")
            } footer: {
                Text("Optional periodic refresh, independent of system triggers.")
            }

            Section {
                Toggle("App launch", isOn: $settings.refreshOnLaunch)
                Toggle("Wake from sleep", isOn: $settings.refreshOnWake)
                Toggle("Screen unlock", isOn: $settings.refreshOnScreenUnlock)
                Toggle("User session active", isOn: $settings.refreshOnSessionActive)
            } header: {
                Text("System triggers")
            } footer: {
                Text("Optional events that refresh usage, independent of the timer.")
            }
        }
        .formStyle(.grouped)
        .macDialogPadding()
    }

    private var accountPage: some View {
        Form {
            Section {
                HStack(alignment: .firstTextBaseline) {
                    Text("WorkosCursorSessionToken")
                        .font(.headline)
                    Spacer()
                    Button {
                        showingTokenHelp = true
                    } label: {
                        Image(systemName: "info.circle")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                            .imageScale(.large)
                    }
                    .buttonStyle(.plain)
                    .help("How to update your Cursor session token")
                    .accessibilityLabel("How to update your Cursor session token")
                }

                Text("This is the cookie / session token the app uses to fetch Cursor usage.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top) {
                    Group {
                        if showToken {
                            TextField("Paste token here", text: $tokenDraft, axis: .vertical)
                                .lineLimit(3...8)
                        } else {
                            SecureField("Paste token here", text: $tokenDraft)
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveToken)

                    Button {
                        showToken.toggle()
                    } label: {
                        Image(systemName: showToken ? "eye.slash" : "eye")
                    }
                    .help(showToken ? "Hide token" : "Show token")
                }

                LabeledContent("Expires") {
                    Text(TokenStore.expirationSummary(ofToken: tokenDraft.isEmpty ? settings.sessionToken : tokenDraft))
                        .foregroundStyle(expirationColor)
                        .multilineTextAlignment(.trailing)
                }

                HStack(spacing: MacUI.Density.gap) {
                    Button("Clear", role: .destructive) {
                        tokenDraft = ""
                        settings.sessionToken = ""
                        detectMessage = nil
                    }
                    .buttonStyle(.macDestructive)

                    Spacer(minLength: 0)

                    Button("Detect from Cursor") {
                        showingDetectToken = true
                    }
                    .buttonStyle(.macSecondary)

                    Button("Save Token") {
                        saveToken()
                    }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSaveToken)
                }

                if let detectMessage {
                    Text(detectMessage)
                        .foregroundStyle(.secondary)
                        .font(.callout)
                }
            } header: {
                Text("Cursor Session")
            } footer: {
                Text("When the token expires, usage refresh fails until you paste a new WorkosCursorSessionToken or detect it again from Cursor.")
            }
        }
        .formStyle(.grouped)
        .macDialogPadding()
    }

    private var backupPage: some View {
        Form {
            Section {
                Toggle("Include session token in export", isOn: $includeTokenInExport)

                HStack(spacing: MacUI.Density.gap) {
                    Button("Import…") {
                        importSettings()
                    }
                    .buttonStyle(.macSecondary)
                    Spacer(minLength: 0)
                    Button("Export…") {
                        exportSettings()
                    }
                    .buttonStyle(.macPrimary)
                }

                if let transferMessage {
                    Text(transferMessage)
                        .foregroundStyle(transferIsError ? .red : .secondary)
                        .font(.callout)
                        .textSelection(.enabled)
                }
            } header: {
                Text("Backup")
            } footer: {
                Text("Export settings to a JSON file, or import from another Mac. Treat exported files as secrets if they include your session token.")
            }
        }
        .formStyle(.grouped)
        .macDialogPadding()
    }

    private var aboutPage: some View {
        Form {
            Section("About") {
                LabeledContent("App", value: "Cursor Usage")
                LabeledContent("Version", value: AppVersion.display)
                LabeledContent("Build", value: AppVersion.build)
            }

            Section {
                Link("Open usage online", destination: URL(string: "https://cursor.com/settings")!)
            } footer: {
                Text("Cursor Usage is a local menu-bar companion for Cursor Pro usage metrics.")
            }
        }
        .formStyle(.grouped)
        .macDialogPadding()
    }

    private var menuBarTemplateFooter: String {
        let tags = MenuBarTemplate.tags.map(\.token).joined(separator: "  ")
        return "Mix any text with reserved tags. Default: \(MenuBarTemplate.defaultTemplate)\n\(tags)"
    }

    private var canSaveToken: Bool {
        TokenStore.normalizeToken(tokenDraft) != TokenStore.normalizeToken(settings.sessionToken)
    }

    private var expirationColor: Color {
        let token = tokenDraft.isEmpty ? settings.sessionToken : tokenDraft
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .secondary
        }
        if TokenStore.isExpired(token) {
            return .red
        }
        if let exp = TokenStore.expirationDate(ofToken: token),
           let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day,
           days <= 7 {
            return .orange
        }
        return .secondary
    }

    private func saveToken() {
        guard canSaveToken else { return }
        let normalized = TokenStore.normalizeToken(tokenDraft)
        tokenDraft = normalized
        settings.sessionToken = normalized
        detectMessage = normalized.isEmpty ? "Token cleared." : "Token saved."
        Task { await viewModel.refresh() }
    }

    private func exportSettings() {
        do {
            let data = try settings.exportJSON(includeSessionToken: includeTokenInExport)
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.json]
            panel.nameFieldStringValue = "cursor-usage-settings.json"
            panel.canCreateDirectories = true
            panel.title = "Export Cursor Usage Settings"
            panel.message = includeTokenInExport
                ? "This file may contain your session token."
                : "Session token will be omitted from this export."

            guard panel.runModal() == .OK, let url = panel.url else {
                return
            }
            try data.write(to: url, options: Data.WritingOptions.atomic)
            transferIsError = false
            transferMessage = "Exported to \(url.lastPathComponent)"
        } catch {
            transferIsError = true
            transferMessage = error.localizedDescription
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Cursor Usage Settings"
        panel.message = "Choose a Cursor Usage settings JSON file."

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            let data = try Data(contentsOf: url)
            try settings.importJSON(from: data)
            tokenDraft = settings.sessionToken
            viewModel.reschedule()
            viewModel.rebuildSystemTriggers()
            Task { await viewModel.refresh() }
            transferIsError = false
            transferMessage = "Imported from \(url.lastPathComponent)"
        } catch {
            transferIsError = true
            transferMessage = error.localizedDescription
        }
    }
}

private struct DetectTokenSheet: View {
    enum Phase {
        case detecting
        case testing
        case ready
        case failed(String)
    }

    let savedToken: String
    let draftToken: String
    let onUseToken: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .detecting
    @State private var detectedToken: String?
    @State private var showDetectedToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: MacUI.Density.iconSize))
                    .foregroundStyle(MacUI.Colors.secondaryText)
                Text("Detect from Cursor")
                    .font(MacUI.headlineFont(scale: 1.15))
                    .foregroundStyle(MacUI.Colors.primaryText)
                Spacer(minLength: 0)
            }
            .frame(height: MacUI.Density.titleBarHeight)
            .padding(.horizontal, MacUI.Density.dialogPad)

            VStack(alignment: .leading, spacing: MacUI.Density.gap) {
                statusSection

                if let detectedToken {
                    tokenValueSection(detectedToken)
                    comparisonTable(detectedToken)
                }
            }
            .padding(.horizontal, MacUI.Density.dialogPad)
            .padding(.bottom, MacUI.Density.gap)

            Rectangle()
                .fill(MacUI.Colors.divider)
                .frame(height: 1)

            MacDialogFooter {
                EmptyView()
            } trailing: {
                HStack(spacing: MacUI.Density.gap) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .buttonStyle(.macSecondary)
                    .keyboardShortcut(.cancelAction)

                    Button("Use new Token") {
                        guard let detectedToken else { return }
                        onUseToken(detectedToken)
                        dismiss()
                    }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canUseNewToken)
                }
            }
        }
        .font(MacUI.bodyFont())
        .foregroundStyle(MacUI.Colors.primaryText)
        .frame(width: 520)
        .fixedSize(horizontal: false, vertical: true)
        .background(MacUI.Colors.sheetFallback.opacity(0.001))
        .task {
            await detect()
        }
    }

    private var canUseNewToken: Bool {
        guard let detectedToken else { return false }
        switch phase {
        case .detecting, .testing:
            return false
        case .ready, .failed:
            return TokenStore.normalizeToken(detectedToken) != TokenStore.normalizeToken(draftToken)
        }
    }

    private var statusSection: some View {
        opaquePanel(title: "Status") {
            VStack(alignment: .leading, spacing: 6) {
                switch phase {
                case .detecting:
                    Label("Reading Cursor’s local session data…", systemImage: "ellipsis.circle")
                        .foregroundStyle(MacUI.Colors.secondaryText)
                case .testing:
                    Label("Testing detected token against Cursor’s API…", systemImage: "network")
                        .foregroundStyle(MacUI.Colors.secondaryText)
                case .ready:
                    Label("Token detected and verified.", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(MacUI.Colors.destructive)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func tokenValueSection(_ token: String) -> some View {
        opaquePanel(title: "Detected value") {
            HStack(alignment: .top, spacing: MacUI.Density.gap) {
                Group {
                    if showDetectedToken {
                        Text(token)
                            .textSelection(.enabled)
                    } else {
                        Text(maskedToken(token))
                            .textSelection(.enabled)
                    }
                }
                .font(.system(size: MacUI.Density.fontSize, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    showDetectedToken.toggle()
                } label: {
                    Image(systemName: showDetectedToken ? "eye.slash" : "eye")
                        .font(.system(size: MacUI.Density.iconSize))
                        .frame(width: MacUI.Density.controlHeight, height: MacUI.Density.controlHeight)
                }
                .buttonStyle(.macSecondary)
                .help(showDetectedToken ? "Hide token" : "Show token")
            }
        }
    }

    private func opaquePanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacUI.calloutFont().weight(.semibold))
                .foregroundStyle(MacUI.Colors.secondaryText)
            content()
        }
        .padding(MacUI.Density.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macOpaqueCard()
    }

    private func comparisonTable(_ token: String) -> some View {
        let normalizedDetected = TokenStore.normalizeToken(token)
        let normalizedSaved = TokenStore.normalizeToken(savedToken)
        let hasSaved = !normalizedSaved.isEmpty
        let isSameToken = hasSaved && normalizedDetected == normalizedSaved
        let alreadyInField = !TokenStore.normalizeToken(draftToken).isEmpty
            && TokenStore.normalizeToken(token) == TokenStore.normalizeToken(draftToken)

        return opaquePanel(title: "Compared to saved") {
            VStack(alignment: .leading, spacing: 0) {
                comparisonHeader

                sheetDivider

                comparisonRow(label: "Token") {
                    VStack(alignment: .leading, spacing: 4) {
                        comparisonBadge(
                            title: hasSaved ? (isSameToken ? "Same" : "Different") : "New",
                            tint: hasSaved ? (isSameToken ? MacUI.Colors.secondaryText : .orange) : MacUI.Colors.accent
                        )
                        Text(maskedToken(token))
                            .font(.system(size: MacUI.Density.fontSize - 2, design: .monospaced))
                            .foregroundStyle(MacUI.Colors.secondaryText)
                            .textSelection(.enabled)
                    }
                } saved: {
                    VStack(alignment: .leading, spacing: 4) {
                        if hasSaved {
                            comparisonBadge(
                                title: isSameToken ? "Same" : "Different",
                                tint: isSameToken ? MacUI.Colors.secondaryText : .orange
                            )
                            Text(maskedToken(savedToken))
                                .font(.system(size: MacUI.Density.fontSize - 2, design: .monospaced))
                                .foregroundStyle(MacUI.Colors.secondaryText)
                                .textSelection(.enabled)
                        } else {
                            Text("None saved")
                                .foregroundStyle(MacUI.Colors.secondaryText)
                        }
                    }
                }

                sheetDivider

                comparisonRow(label: "Expires") {
                    expirationCell(for: token)
                } saved: {
                    if hasSaved {
                        expirationCell(for: savedToken)
                    } else {
                        Text("—")
                            .foregroundStyle(MacUI.Colors.secondaryText)
                    }
                }

                sheetDivider

                Text(comparisonVerdict(
                    hasSaved: hasSaved,
                    isSameToken: isSameToken,
                    detected: token,
                    saved: savedToken,
                    alreadyInField: alreadyInField
                ))
                .font(MacUI.calloutFont())
                .foregroundStyle(MacUI.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var sheetDivider: some View {
        Rectangle()
            .fill(MacUI.Colors.divider)
            .frame(height: 1)
            .padding(.vertical, 8)
    }

    private var comparisonHeader: some View {
        HStack(alignment: .top, spacing: MacUI.Density.gap) {
            Color.clear.frame(width: 64)
            Text("Detected")
                .font(MacUI.calloutFont().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Saved")
                .font(MacUI.calloutFont().weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func comparisonRow<Detected: View, Saved: View>(
        label: String,
        @ViewBuilder detected: () -> Detected,
        @ViewBuilder saved: () -> Saved
    ) -> some View {
        HStack(alignment: .top, spacing: MacUI.Density.gap) {
            Text(label)
                .font(MacUI.calloutFont().weight(.medium))
                .foregroundStyle(MacUI.Colors.secondaryText)
                .frame(width: 64, alignment: .leading)
            detected()
                .frame(maxWidth: .infinity, alignment: .leading)
            saved()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func comparisonBadge(title: String, tint: Color) -> some View {
        Text(title)
            .font(MacUI.captionFont().weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func expirationCell(for token: String) -> some View {
        let summary = shortExpirationSummary(ofToken: token)
        return VStack(alignment: .leading, spacing: 2) {
            Text(summary.primary)
                .foregroundStyle(expirationColor(for: token))
            if let secondary = summary.secondary {
                Text(secondary)
                    .font(MacUI.captionFont())
                    .foregroundStyle(MacUI.Colors.secondaryText)
            }
        }
    }

    private func shortExpirationSummary(ofToken raw: String, now: Date = Date()) -> (primary: String, secondary: String?) {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ("No token", nil) }
        guard let exp = TokenStore.expirationDate(ofToken: trimmed) else {
            return ("Unknown", nil)
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        let stamped = formatter.string(from: exp)
        if exp <= now {
            return ("Expired", stamped)
        }
        let days = Calendar.current.dateComponents([.day], from: now, to: exp).day ?? 0
        let relative: String
        if days == 0 {
            relative = "Today"
        } else if days == 1 {
            relative = "Tomorrow"
        } else {
            relative = "In \(days) days"
        }
        return (relative, stamped)
    }

    private func comparisonVerdict(
        hasSaved: Bool,
        isSameToken: Bool,
        detected: String,
        saved: String,
        alreadyInField: Bool
    ) -> String {
        var parts: [String] = []

        if !hasSaved {
            parts.append("No saved token to compare")
        } else if isSameToken {
            parts.append("Same token")
        } else {
            parts.append("Different token")
        }

        if hasSaved,
           let detectedExp = TokenStore.expirationDate(ofToken: detected),
           let savedExp = TokenStore.expirationDate(ofToken: saved) {
            if detectedExp == savedExp {
                parts.append("same expiration")
            } else if detectedExp > savedExp {
                let days = Calendar.current.dateComponents([.day], from: savedExp, to: detectedExp).day ?? 0
                if days > 0 {
                    parts.append("expires \(days) day\(days == 1 ? "" : "s") later")
                } else {
                    parts.append("expires later")
                }
            } else {
                let days = Calendar.current.dateComponents([.day], from: detectedExp, to: savedExp).day ?? 0
                if days > 0 {
                    parts.append("expires \(days) day\(days == 1 ? "" : "s") sooner")
                } else {
                    parts.append("expires sooner")
                }
            }
        }

        var line = parts.joined(separator: " · ")
        if alreadyInField {
            line += ". Already in the Account field"
        }
        return line + "."
    }

    private func expirationColor(for token: String) -> Color {
        if token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return MacUI.Colors.secondaryText
        }
        if TokenStore.isExpired(token) {
            return MacUI.Colors.destructive
        }
        if let exp = TokenStore.expirationDate(ofToken: token),
           let days = Calendar.current.dateComponents([.day], from: Date(), to: exp).day,
           days <= 7 {
            return .orange
        }
        return MacUI.Colors.primaryText
    }

    private func maskedToken(_ token: String) -> String {
        let normalized = TokenStore.normalizeToken(token)
        guard normalized.count > 12 else {
            return String(repeating: "•", count: max(normalized.count, 8))
        }
        let prefix = normalized.prefix(6)
        let suffix = normalized.suffix(4)
        return "\(prefix)…\(suffix)"
    }

    private func detect() async {
        phase = .detecting
        detectedToken = nil

        guard let token = await TokenStore.autoDetectToken() else {
            phase = .failed("Could not find a token in Cursor’s local database.")
            return
        }

        detectedToken = token
        phase = .testing

        do {
            _ = try await UsageClient().fetchUsage(token: token)
            phase = .ready
        } catch {
            phase = .failed("Detected a token, but it failed verification: \(error.localizedDescription)")
        }
    }
}

private struct TokenHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "key.fill")
                    .font(.system(size: MacUI.Density.iconSize))
                    .foregroundStyle(MacUI.Colors.secondaryText)
                Text("Update Cursor Session Token")
                    .font(MacUI.headlineFont(scale: 1.15))
                    .foregroundStyle(MacUI.Colors.primaryText)
                Spacer(minLength: 0)
            }
            .frame(height: MacUI.Density.titleBarHeight)
            .padding(.horizontal, MacUI.Density.dialogPad)

            ScrollView {
                VStack(alignment: .leading, spacing: MacUI.Density.gap) {
                    Text("This app authenticates with the WorkosCursorSessionToken cookie from cursor.com (same value Cursor stores locally).")
                        .foregroundStyle(MacUI.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    helpPanel(title: "Option A — Copy from browser") {
                        step(1, "Open https://cursor.com in your browser and sign in.")
                        step(2, "Open Developer Tools (Safari: Develop → Show Web Inspector; Chrome: View → Developer → Developer Tools).")
                        step(3, "Go to Storage / Application → Cookies → https://cursor.com.")
                        step(4, "Find the cookie named WorkosCursorSessionToken and copy its value.")
                        step(5, "Paste it into Settings → Account, then click Save Token.")
                    }

                    helpPanel(title: "Option B — Detect from Cursor app") {
                        step(1, "Make sure the Cursor desktop app is installed and you are signed in.")
                        step(2, "In Settings → Account, click Detect from Cursor.")
                        step(3, "Review the detected value and expiration, then click Use new Token to fill the field.")
                        step(4, "Click Save Token, then Refresh from Details.")
                    }

                    Text("When the token expires, usage requests return an auth error. Update it with Option A or B, then Refresh from Details.")
                        .font(MacUI.calloutFont())
                        .foregroundStyle(MacUI.Colors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, MacUI.Density.dialogPad)
                .padding(.bottom, MacUI.Density.dialogPad)
            }

            Rectangle()
                .fill(MacUI.Colors.divider)
                .frame(height: 1)

            MacDialogFooter {
                EmptyView()
            } trailing: {
                Button("Done") { dismiss() }
                    .buttonStyle(.macPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(MacUI.bodyFont())
        .foregroundStyle(MacUI.Colors.primaryText)
        .frame(minWidth: 560, idealWidth: 600, maxWidth: 720,
               minHeight: 520, idealHeight: 560, maxHeight: 800)
    }

    private func helpPanel<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(MacUI.calloutFont().weight(.semibold))
                .foregroundStyle(MacUI.Colors.secondaryText)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
        }
        .padding(MacUI.Density.gap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .macOpaqueCard()
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(MacUI.Colors.secondaryText)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
