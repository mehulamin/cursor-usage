import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var viewModel: UsageViewModel
    @State private var tokenDraft: String = ""
    @State private var showToken = false
    @State private var detectMessage: String?

    var body: some View {
        Form {
            appearanceSection
            menuBarSection
            refreshSection
            accountSection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 560)
        .font(.system(size: 13 * settings.fontSize.scale))
        .onAppear {
            tokenDraft = settings.sessionToken
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Font Size", selection: $settings.fontSize) {
                ForEach(FontSizeOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Font size")
        }
    }

    private var menuBarSection: some View {
        Section {
            LabeledContent("Format", value: "80% * 11d")
        } header: {
            Text("Menu Bar")
        } footer: {
            Text("Shows total usage percent and days left in the billing cycle. Open Details for the full breakdown.")
        }
    }

    private var refreshSection: some View {
        Section("Refresh") {
            Stepper(value: $settings.refreshIntervalMinutes, in: 5...60, step: 5) {
                Text("Every \(settings.refreshIntervalMinutes) minutes")
            }
            .onChange(of: settings.refreshIntervalMinutes) { _, _ in
                viewModel.reschedule()
            }
        }
    }

    private var accountSection: some View {
        Section {
            HStack {
                Group {
                    if showToken {
                        TextField("Session token", text: $tokenDraft)
                    } else {
                        SecureField("Session token", text: $tokenDraft)
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

            HStack {
                Button("Save Token") {
                    saveToken()
                }
                .keyboardShortcut(.defaultAction)

                Button("Detect from Cursor") {
                    detectMessage = "Detecting…"
                    Task {
                        if let token = await TokenStore.autoDetectToken() {
                            tokenDraft = token
                            settings.sessionToken = token
                            detectMessage = "Token detected from Cursor."
                            await viewModel.refresh()
                        } else {
                            detectMessage = "Could not find a token in Cursor’s local database."
                        }
                    }
                }

                Button("Clear", role: .destructive) {
                    tokenDraft = ""
                    settings.sessionToken = ""
                    detectMessage = nil
                }
            }

            if let detectMessage {
                Text(detectMessage)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        } header: {
            Text("Account")
        } footer: {
            Text("Paste the WorkosCursorSessionToken cookie from cursor.com, or detect the token Cursor stores locally.")
        }
    }

    private var aboutSection: some View {
        Section("About") {
            LabeledContent("Version", value: AppVersion.display)
            LabeledContent("Build", value: AppVersion.build)
        }
    }

    private func saveToken() {
        let normalized = TokenStore.normalizeToken(tokenDraft)
        tokenDraft = normalized
        settings.sessionToken = normalized
        detectMessage = normalized.isEmpty ? "Token cleared." : "Token saved."
        Task { await viewModel.refresh() }
    }
}
