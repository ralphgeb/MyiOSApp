import SwiftUI
import UIKit

/// The colors the app's own screens use right now (the original look until the unlock is bought).
struct AppTheme {
    let scheme: ColorScheme

    private var colors: SharedSettings.ColorSet {
        SharedSettings.effectiveColorSettings.resolved(for: scheme)
    }

    var ink: Color { colors.text?.color ?? .primary }
    var accent: Color { colors.highlight?.color ?? .orange }
    var accentText: Color { colors.highlightText?.color ?? .black }

    var background: Color {
        colors.background?.color ?? (scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.118) : Color(.systemBackground))
    }

    /// Rows and cards: the chosen card color, or a soft step away from the background.
    var card: Color {
        if let c = colors.card { return c.color }
        if let bg = colors.background {
            let fallbackInk = bg.luminance > 0.5 ? RGBA(hex: 0x000000) : RGBA(hex: 0xFFFFFF)
            return bg.mixed(with: colors.text ?? fallbackInk, 0.07).color
        }
        return scheme == .dark ? Color(white: 0.17) : Color(.secondarySystemBackground)
    }

    /// For the title bar: nil while the original look is on (the system decides).
    var barScheme: ColorScheme? {
        guard let bg = colors.background else { return nil }
        return bg.luminance > 0.5 ? .light : .dark
    }
}

/// Light, Dark or Automatic for the whole app, set on its windows. (SwiftUI's preferredColorScheme
/// often stays stuck on Dark or Light after going back to nil, so Automatic didn't follow the iPhone.)
@MainActor enum InterfaceStyle {
    static func apply() {
        let style: UIUserInterfaceStyle
        switch SharedSettings.appearanceMode {
        case .automatic: style = .unspecified
        case .light: style = .light
        case .dark: style = .dark
        }
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            for window in scene.windows where window.overrideUserInterfaceStyle != style {
                window.overrideUserInterfaceStyle = style
            }
        }
    }
}

extension Notification.Name {
    static let colorsChanged = Notification.Name("colorsChanged")
}
