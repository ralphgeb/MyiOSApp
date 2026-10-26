import SwiftUI
import UIKit

extension RGBA {
    init(hex: UInt32) {
        self.init(r: Double((hex >> 16) & 0xFF) / 255, g: Double((hex >> 8) & 0xFF) / 255,
                  b: Double(hex & 0xFF) / 255, a: 1)
    }

    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    /// This color moved toward `other` by `t` (0...1).
    func mixed(with other: RGBA, _ t: Double) -> RGBA {
        RGBA(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t, a: 1)
    }
}

/// A ready-made look, shared with the sister app: a main (text) color, a background and a card color
/// for Light and Dark mode, plus one accent.
struct LookPreset: Identifiable {
    let id: String
    let name: String
    let light: (ink: RGBA, background: RGBA, card: RGBA)
    let dark: (ink: RGBA, background: RGBA, card: RGBA)
    let accent: RGBA

    private func set(_ p: (ink: RGBA, background: RGBA, card: RGBA)) -> SharedSettings.ColorSet {
        var s = SharedSettings.ColorSet()
        s.background = p.background
        s.text = p.ink
        s.card = p.card
        s.highlight = accent
        s.highlightText = accent.luminance > 0.6 ? RGBA(hex: 0x000000) : RGBA(hex: 0xFFFFFF)
        return s
    }

    var lightSet: SharedSettings.ColorSet { set(light) }
    var darkSet: SharedSettings.ColorSet { set(dark) }

    static let all: [LookPreset] = [
        LookPreset(id: "graphite", name: "Graphite",
                   light: (RGBA(hex: 0x121214), RGBA(hex: 0xF9F9F7), RGBA(hex: 0xFFFFFF)),
                   dark: (RGBA(hex: 0xF2F2ED), RGBA(hex: 0x090909), RGBA(hex: 0x171717)),
                   accent: RGBA(hex: 0xFF6129)),
        LookPreset(id: "ocean", name: "Ocean",
                   light: (RGBA(hex: 0x0E2A47), RGBA(hex: 0xF4F7FA), RGBA(hex: 0xFFFFFF)),
                   dark: (RGBA(hex: 0xE4EEF7), RGBA(hex: 0x07111C), RGBA(hex: 0x0F1C2B)),
                   accent: RGBA(hex: 0x1FC8B4)),
        LookPreset(id: "forest", name: "Forest",
                   light: (RGBA(hex: 0x1C3324), RGBA(hex: 0xF5F7F3), RGBA(hex: 0xFFFFFF)),
                   dark: (RGBA(hex: 0xE5EFE6), RGBA(hex: 0x08100B), RGBA(hex: 0x111C15)),
                   accent: RGBA(hex: 0xE8B04A)),
        LookPreset(id: "mono", name: "Mono",
                   light: (RGBA(hex: 0x000000), RGBA(hex: 0xFFFFFF), RGBA(hex: 0xF3F3F3)),
                   dark: (RGBA(hex: 0xFFFFFF), RGBA(hex: 0x000000), RGBA(hex: 0x141414)),
                   accent: RGBA(hex: 0xE5484D)),
        LookPreset(id: "dusk", name: "Dusk",
                   light: (RGBA(hex: 0x2B2540), RGBA(hex: 0xF7F6FA), RGBA(hex: 0xFFFFFF)),
                   dark: (RGBA(hex: 0xECE9F6), RGBA(hex: 0x0D0B14), RGBA(hex: 0x18151F)),
                   accent: RGBA(hex: 0xFF8A65)),
        LookPreset(id: "sand", name: "Sand",
                   light: (RGBA(hex: 0x3A2E27), RGBA(hex: 0xF7F3EE), RGBA(hex: 0xFFFDFA)),
                   dark: (RGBA(hex: 0xF3ECE4), RGBA(hex: 0x120E0B), RGBA(hex: 0x1D1814)),
                   accent: RGBA(hex: 0x3D8BFD)),
    ]
}

/// The colors the app's own screens use right now (the original look until the unlock is bought).
struct AppTheme {
    let scheme: ColorScheme

    private var set: SharedSettings.ColorSet {
        SharedSettings.isPro ? SharedSettings.colorSettings.resolved(for: scheme) : SharedSettings.ColorSet()
    }

    var ink: Color { set.text?.color ?? .primary }
    var accent: Color { set.highlight?.color ?? .orange }
    var accentText: Color { set.highlightText?.color ?? .black }

    var background: Color {
        set.background?.color ?? (scheme == .dark ? Color(red: 0.11, green: 0.11, blue: 0.118) : Color(.systemBackground))
    }

    /// Rows and cards: the chosen card color, or a soft step away from the background.
    var card: Color {
        if let c = set.card { return c.color }
        if let bg = set.background {
            let fallbackInk = bg.luminance > 0.5 ? RGBA(hex: 0x000000) : RGBA(hex: 0xFFFFFF)
            return bg.mixed(with: set.text ?? fallbackInk, 0.07).color
        }
        return scheme == .dark ? Color(white: 0.17) : Color(.secondarySystemBackground)
    }

    /// For the title bar: nil while the original look is on (the system decides).
    var barScheme: ColorScheme? {
        guard let bg = set.background else { return nil }
        return bg.luminance > 0.5 ? .light : .dark
    }
}

extension Notification.Name {
    static let colorsChanged = Notification.Name("colorsChanged")
}
