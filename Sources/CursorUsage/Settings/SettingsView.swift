import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum SettingsPage: String, CaseIterable, Identifiable, Hashable {
    case general
    case account
    case backup
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .account: return "Account"
        case .backup: return "Backup"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .account: return "key.fill"
        case .backup: return "square.and.arrow.up.on.square"
        case .about: return "info.circle"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var selectedPage: SettingsPage? = .general
    @State private var tokenDraft: String = ""
    @State private var showToken = false
    @State private var detectMessage: String?
    @State private var isDetecting = false
    @State private var confirmingDetect = false
    @State private var includeTokenInExport = true
    @State private var transferMessage: String?
    @State private var transferIsError = false
    @State private var showingTokenHelp = false
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
        .font(.system(size: 13 * settings.fontSize.scale))
        .frame(minWidth: 640, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
        .onAppear {
            tokenDraft = settings.sessionToken
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
    }

    // MARK: - Pages

    private var generalPage: some View {
        Form {
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
                .disabled(settings.menuBarTemplate == MenuBarTemplate.defaultTemplate)
            } header: {
                Text("Menu Bar")
            } footer: {
                Text(menuBarTemplateFooter)
            }

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
        .padding()
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

                HStack {
                    Button("Save Token") {
                        saveToken()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSaveToken)

                    Button("Detect from Cursor") {
                        confirmingDetect = true
                    }
                    .disabled(isDetecting)

                    Button("Clear", role: .destructive) {
                        tokenDraft = ""
                        settings.sessionToken = ""
                        detectMessage = nil
                    }
                }
                .confirmationDialog(
                    "Detect token from Cursor?",
                    isPresented: $confirmingDetect,
                    titleVisibility: .visible
                ) {
                    Button("Detect and Test") {
                        detectAndTestToken()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Cursor Usage will read a session token from Cursor’s local data, test it against Cursor’s API, and only then fill the field so you can save it.")
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
        .padding()
    }

    private var backupPage: some View {
        Form {
            Section {
                Toggle("Include session token in export", isOn: $includeTokenInExport)

                HStack {
                    Button("Export…") {
                        exportSettings()
                    }
                    Button("Import…") {
                        importSettings()
                    }
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
        .padding()
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
        .padding()
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

    private func detectAndTestToken() {
        isDetecting = true
        detectMessage = "Detecting…"
        Task {
            defer { isDetecting = false }

            guard let token = await TokenStore.autoDetectToken() else {
                detectMessage = "Could not find a token in Cursor’s local database."
                return
            }

            detectMessage = "Testing detected token…"
            do {
                _ = try await UsageClient().fetchUsage(token: token)
                tokenDraft = token
                detectMessage = "Token detected and verified. Click Save Token to keep it."
            } catch {
                detectMessage = "Detected a token, but it failed verification: \(error.localizedDescription)"
            }
        }
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

private struct TokenHelpSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Update Cursor Session Token", systemImage: "key.fill")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("This app authenticates with the WorkosCursorSessionToken cookie from cursor.com (same value Cursor stores locally).")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GroupBox("Option A — Copy from browser") {
                        VStack(alignment: .leading, spacing: 8) {
                            step(1, "Open https://cursor.com in your browser and sign in.")
                            step(2, "Open Developer Tools (Safari: Develop → Show Web Inspector; Chrome: View → Developer → Developer Tools).")
                            step(3, "Go to Storage / Application → Cookies → https://cursor.com.")
                            step(4, "Find the cookie named WorkosCursorSessionToken and copy its value.")
                            step(5, "Paste it into Settings → Account, then click Save Token.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    GroupBox("Option B — Detect from Cursor app") {
                        VStack(alignment: .leading, spacing: 8) {
                            step(1, "Make sure the Cursor desktop app is installed and you are signed in.")
                            step(2, "In Settings → Account, click Detect from Cursor and confirm.")
                            step(3, "If the token is found and verifies, click Save Token, then Refresh from Details.")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 4)
                    }

                    Text("When the token expires, usage requests return an auth error. Update it with Option A or B, then Refresh from Details.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
        }
        .frame(minWidth: 560, idealWidth: 600, maxWidth: 720,
               minHeight: 520, idealHeight: 560, maxHeight: 800)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number).")
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .frame(width: 20, alignment: .trailing)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
