import AppKit
import SwiftUI

/// Standard density + Liquid Glass material — single source of truth for app chrome and controls.
/// Content panels stay opaque; glass is reserved for navigation/control layers (HIG).
enum MacUI {
    // MARK: - Density (Standard)

    enum Density {
        static let controlHeight: CGFloat = 28
        static let fontSize: CGFloat = 13
        static let cornerRadius: CGFloat = 6
        static let gap: CGFloat = 12
        static let buttonPaddingH: CGFloat = 14
        static let dialogPad: CGFloat = 20
        static let iconSize: CGFloat = 16
        static let titleBarHeight: CGFloat = 44
        static let switchWidth: CGFloat = 32
        static let switchHeight: CGFloat = 18
        static let checkboxRadius: CGFloat = cornerRadius * 0.55
        static let spinnerSize: CGFloat = iconSize * 1.4
        static let progressStroke: CGFloat = 2.5
        static let menuCheckColumn: CGFloat = 14
        static let segmentedInternalPad: CGFloat = 2
        static let focusHaloWidth: CGFloat = 3
    }

    // MARK: - Color roles

    enum Colors {
        /// Opaque content / card layer (never glass).
        static let cardBackground = Color.mac(light: 0xFFFFFF, dark: 0x3A3A3C)
        /// Soft wash behind glass so refraction has something to sample.
        static let ambientWash = Color.mac(light: 0xECECEC, dark: 0x1E1E20)
        static let windowBackground = Color.mac(light: 0xF3F3F4, dark: 0x242426)
        static let sheetFallback = Color.mac(light: 0xF6F6F6, dark: 0x2C2C2E)
        static let inputBackground = Color.mac(
            light: 0xFFFFFF, lightAlpha: 1,
            dark: 0xFFFFFF, darkAlpha: 0.07
        )
        static let primaryText = Color.mac(light: 0x1D1D1F, dark: 0xF5F5F7)
        static let secondaryText = Color.mac(light: 0x6E6E73, dark: 0x98989D)
        static let tertiaryText = Color.mac(light: 0xAEAEB2, dark: 0x6E6E73)
        static let border = Color.mac(
            light: 0x000000, lightAlpha: 0.10,
            dark: 0xFFFFFF, darkAlpha: 0.10
        )
        static let divider = Color.mac(
            light: 0x000000, lightAlpha: 0.08,
            dark: 0xFFFFFF, darkAlpha: 0.08
        )
        static let accent = Color.mac(light: 0x007AFF, dark: 0x0A84FF)
        static let destructive = Color.mac(light: 0xFF3B30, dark: 0xFF453A)
        static let controlBorder = Color.mac(
            light: 0x000000, lightAlpha: 0.16,
            dark: 0xFFFFFF, darkAlpha: 0.16
        )
        static let trackOff = Color.mac(light: 0xD7D7DC, dark: 0x5A5A5E)
        static let titleBar = Color.mac(light: 0xE4E4E6, dark: 0x3B3B3D)
        static let segmentTrack = Color.mac(
            light: 0xE3E3E6, lightAlpha: 1,
            dark: 0xFFFFFF, darkAlpha: 0.06
        )
        static let scrim = Color.mac(
            light: 0x000000, lightAlpha: 0.06,
            dark: 0x000000, darkAlpha: 0.35
        )
        static let focusHalo = Color.mac(
            light: 0x007AFF, lightAlpha: 0.18,
            dark: 0x0A84FF, darkAlpha: 0.28
        )
        /// Translucent glass fills (~0.38–0.55 alpha) for chrome surfaces only.
        static let glassFill = Color.mac(
            light: 0xF6F6F6, lightAlpha: 0.48,
            dark: 0x2C2C2E, darkAlpha: 0.52
        )
        static let glassBorder = Color.mac(
            light: 0xFFFFFF, lightAlpha: 0.55,
            dark: 0xFFFFFF, darkAlpha: 0.14
        )
        static let glassSpecular = Color.mac(
            light: 0xFFFFFF, lightAlpha: 0.80,
            dark: 0xFFFFFF, darkAlpha: 0.14
        )
    }

    // MARK: - Typography

    static func bodyFont(scale: CGFloat = 1) -> Font {
        .system(size: Density.fontSize * scale)
    }

    static func headlineFont(scale: CGFloat = 1) -> Font {
        .system(size: Density.fontSize * scale, weight: .semibold)
    }

    static func calloutFont(scale: CGFloat = 1) -> Font {
        .system(size: (Density.fontSize - 1) * scale)
    }

    static func captionFont(scale: CGFloat = 1) -> Font {
        .system(size: (Density.fontSize - 2) * scale)
    }
}

// MARK: - Dynamic color helper

extension Color {
    static func mac(
        light: Int, lightAlpha: CGFloat = 1,
        dark: Int, darkAlpha: CGFloat = 1
    ) -> Color {
        Color(nsColor: NSColor(name: nil, dynamicProvider: { appearance in
            let darkMode = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = darkMode ? dark : light
            let alpha = darkMode ? darkAlpha : lightAlpha
            return NSColor(
                srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha
            )
        }))
    }
}

// MARK: - Glass chrome (one layer only)

struct MacGlassChrome: ViewModifier {
    var cornerRadius: CGFloat = MacUI.Density.cornerRadius

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(MacUI.Colors.ambientWash.opacity(0.35))
            }
            .glassEffect(.regular, in: .rect(cornerRadius: cornerRadius))
    }
}

struct MacOpaqueCard: ViewModifier {
    var cornerRadius: CGFloat = MacUI.Density.cornerRadius

    func body(content: Content) -> some View {
        content
            .background(
                MacUI.Colors.cardBackground,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(MacUI.Colors.border, lineWidth: 1)
            )
    }
}

extension View {
    /// Liquid Glass on chrome surfaces (popover shell, sheet frame, toolbars).
    func macGlassChrome(cornerRadius: CGFloat = MacUI.Density.cornerRadius) -> some View {
        modifier(MacGlassChrome(cornerRadius: cornerRadius))
    }

    /// Opaque content panel — never glass, even in a glass-material app.
    func macOpaqueCard(cornerRadius: CGFloat = MacUI.Density.cornerRadius) -> some View {
        modifier(MacOpaqueCard(cornerRadius: cornerRadius))
    }

    func macDialogPadding() -> some View {
        padding(MacUI.Density.dialogPad)
    }

    func macControlHeight() -> some View {
        frame(height: MacUI.Density.controlHeight)
    }
}

// MARK: - Push buttons (solid fills nested inside glass containers)

enum MacButtonRole {
    case primary
    case secondary
    case destructive
}

struct MacPushButtonStyle: ButtonStyle {
    var role: MacButtonRole = .secondary
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(MacUI.bodyFont())
            .padding(.horizontal, MacUI.Density.buttonPaddingH)
            .frame(height: MacUI.Density.controlHeight)
            .background(background(configuration), in: RoundedRectangle(
                cornerRadius: MacUI.Density.cornerRadius,
                style: .continuous
            ))
            .overlay {
                if role != .primary {
                    RoundedRectangle(cornerRadius: MacUI.Density.cornerRadius, style: .continuous)
                        .strokeBorder(MacUI.Colors.controlBorder, lineWidth: 1)
                }
            }
            .overlay {
                if role == .primary {
                    RoundedRectangle(cornerRadius: MacUI.Density.cornerRadius, style: .continuous)
                        .strokeBorder(MacUI.Colors.glassSpecular.opacity(0.55), lineWidth: 1)
                        .blendMode(.plusLighter)
                        .padding(0.5)
                }
            }
            .foregroundStyle(foreground)
            .brightness(configuration.isPressed ? -0.12 : 0)
            .opacity(isEnabled ? 1 : 0.4)
            .saturation(isEnabled ? 1 : 0.6)
            .contentShape(RoundedRectangle(cornerRadius: MacUI.Density.cornerRadius, style: .continuous))
    }

    private var foreground: Color {
        switch role {
        case .primary: return .white
        case .secondary: return MacUI.Colors.primaryText
        case .destructive: return MacUI.Colors.destructive
        }
    }

    private func background(_ configuration: Configuration) -> Color {
        switch role {
        case .primary:
            return MacUI.Colors.accent
        case .secondary, .destructive:
            return MacUI.Colors.inputBackground
        }
    }
}

extension ButtonStyle where Self == MacPushButtonStyle {
    static var macPrimary: MacPushButtonStyle { MacPushButtonStyle(role: .primary) }
    static var macSecondary: MacPushButtonStyle { MacPushButtonStyle(role: .secondary) }
    static var macDestructive: MacPushButtonStyle { MacPushButtonStyle(role: .destructive) }
}

// MARK: - Determinate progress (Standard track)

struct MacProgressBar: View {
    var value: Double
    var total: Double = 100
    var tint: Color = MacUI.Colors.accent

    var body: some View {
        GeometryReader { geo in
            let fraction = total > 0 ? min(max(value / total, 0), 1) : 0
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(MacUI.Colors.trackOff)
                Capsule()
                    .fill(tint)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? 4 : 0))
            }
        }
        .frame(height: max(4, MacUI.Density.controlHeight * 0.18))
        .accessibilityHidden(true)
    }
}

// MARK: - Dialog footer layout

struct MacDialogFooter<Leading: View, Trailing: View>: View {
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    init(
        @ViewBuilder leading: @escaping () -> Leading = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: MacUI.Density.gap) {
            leading()
            Spacer(minLength: MacUI.Density.gap)
            trailing()
        }
        .padding(.horizontal, MacUI.Density.dialogPad)
        .padding(.vertical, 14)
    }
}
