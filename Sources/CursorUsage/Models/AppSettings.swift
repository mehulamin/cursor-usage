import Combine
import Foundation
import SwiftUI

enum FontSizeOption: String, CaseIterable, Identifiable {
    case small
    case medium
    case large
    case extraLarge

    var id: String { rawValue }

    var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .extraLarge: return "Extra Large"
        }
    }

    var scale: CGFloat {
        switch self {
        case .small: return 0.90
        case .medium: return 1.00
        case .large: return 1.15
        case .extraLarge: return 1.30
        }
    }

    var menuBarPointSize: CGFloat {
        switch self {
        case .small: return 13
        case .medium: return 14
        case .large: return 15
        case .extraLarge: return 16
        }
    }
}

/// JSON schema for settings backup / restore.
struct SettingsFile: Codable, Equatable {
    var formatVersion: Int = 1
    var fontSize: String
    var refreshIntervalMinutes: Int
    var sessionToken: String?
    var showAuto: Bool?
    var showAPI: Bool?
    var showTotal: Bool?
    var showDaysLeft: Bool?
    var showEstimate: Bool?
    var showSpend: Bool?
}

enum SettingsTransferError: LocalizedError {
    case encodeFailed
    case decodeFailed
    case invalidFontSize(String)

    var errorDescription: String? {
        switch self {
        case .encodeFailed: return "Could not encode settings to JSON."
        case .decodeFailed: return "Could not read settings from that file."
        case .invalidFontSize(let value): return "Unknown font size “\(value)”."
        }
    }
}

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults = UserDefaults.standard

    @Published var fontSize: FontSizeOption {
        didSet { defaults.set(fontSize.rawValue, forKey: Keys.fontSize) }
    }
    @Published var showAuto: Bool {
        didSet { defaults.set(showAuto, forKey: Keys.showAuto) }
    }
    @Published var showAPI: Bool {
        didSet { defaults.set(showAPI, forKey: Keys.showAPI) }
    }
    @Published var showTotal: Bool {
        didSet { defaults.set(showTotal, forKey: Keys.showTotal) }
    }
    @Published var showDaysLeft: Bool {
        didSet { defaults.set(showDaysLeft, forKey: Keys.showDaysLeft) }
    }
    @Published var showEstimate: Bool {
        didSet { defaults.set(showEstimate, forKey: Keys.showEstimate) }
    }
    @Published var showSpend: Bool {
        didSet { defaults.set(showSpend, forKey: Keys.showSpend) }
    }
    @Published var refreshIntervalMinutes: Int {
        didSet { defaults.set(refreshIntervalMinutes, forKey: Keys.refreshIntervalMinutes) }
    }
    @Published var sessionToken: String {
        didSet { defaults.set(sessionToken, forKey: Keys.sessionToken) }
    }

    private enum Keys {
        static let fontSize = "fontSize"
        static let showAuto = "showAuto"
        static let showAPI = "showAPI"
        static let showTotal = "showTotal"
        static let showDaysLeft = "showDaysLeft"
        static let showEstimate = "showEstimate"
        static let showSpend = "showSpend"
        static let refreshIntervalMinutes = "refreshIntervalMinutes"
        static let sessionToken = "sessionToken"
    }

    private init() {
        let raw = defaults.string(forKey: Keys.fontSize) ?? FontSizeOption.medium.rawValue
        fontSize = FontSizeOption(rawValue: raw) ?? .medium
        showAuto = defaults.object(forKey: Keys.showAuto) as? Bool ?? true
        showAPI = defaults.object(forKey: Keys.showAPI) as? Bool ?? true
        showTotal = defaults.object(forKey: Keys.showTotal) as? Bool ?? true
        showDaysLeft = defaults.object(forKey: Keys.showDaysLeft) as? Bool ?? true
        showEstimate = defaults.object(forKey: Keys.showEstimate) as? Bool ?? false
        showSpend = defaults.object(forKey: Keys.showSpend) as? Bool ?? false
        refreshIntervalMinutes = defaults.object(forKey: Keys.refreshIntervalMinutes) as? Int ?? 15
        sessionToken = defaults.string(forKey: Keys.sessionToken) ?? ""
    }

    func makeExportPayload(includeSessionToken: Bool) -> SettingsFile {
        SettingsFile(
            formatVersion: 1,
            fontSize: fontSize.rawValue,
            refreshIntervalMinutes: refreshIntervalMinutes,
            sessionToken: includeSessionToken ? sessionToken : nil,
            showAuto: showAuto,
            showAPI: showAPI,
            showTotal: showTotal,
            showDaysLeft: showDaysLeft,
            showEstimate: showEstimate,
            showSpend: showSpend
        )
    }

    func exportJSON(includeSessionToken: Bool) throws -> Data {
        let payload = makeExportPayload(includeSessionToken: includeSessionToken)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            return try encoder.encode(payload)
        } catch {
            throw SettingsTransferError.encodeFailed
        }
    }

    func applyImport(_ file: SettingsFile) throws {
        guard let size = FontSizeOption(rawValue: file.fontSize) else {
            throw SettingsTransferError.invalidFontSize(file.fontSize)
        }
        fontSize = size
        refreshIntervalMinutes = max(5, min(60, file.refreshIntervalMinutes))
        if let token = file.sessionToken {
            sessionToken = TokenStore.normalizeToken(token)
        }
        if let value = file.showAuto { showAuto = value }
        if let value = file.showAPI { showAPI = value }
        if let value = file.showTotal { showTotal = value }
        if let value = file.showDaysLeft { showDaysLeft = value }
        if let value = file.showEstimate { showEstimate = value }
        if let value = file.showSpend { showSpend = value }
    }

    func importJSON(from data: Data) throws {
        let decoder = JSONDecoder()
        let file: SettingsFile
        do {
            file = try decoder.decode(SettingsFile.self, from: data)
        } catch {
            throw SettingsTransferError.decodeFailed
        }
        try applyImport(file)
    }
}
