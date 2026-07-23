import SwiftUI

private struct FontScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var fontScale: CGFloat {
        get { self[FontScaleKey.self] }
        set { self[FontScaleKey.self] = newValue }
    }
}

extension View {
    func scaledFont(_ style: Font.TextStyle, scale: CGFloat) -> some View {
        self.font(.system(style).weight(.regular))
            .scaleEffect(scale, anchor: .leading)
    }
}
