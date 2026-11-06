import SwiftUI

/// The first time Ahead opens: the logo draws itself, then the name, then the line under it.
/// A second page explains what the app does and what it needs.
struct OnboardingView: View {
    let finish: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var page = 0
    @State private var forward = true
    @State private var tick = 0       // bumps when the chosen theme changes, so every page redraws

    private var theme: AppTheme { _ = tick; return AppTheme(scheme: scheme) }

    var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            Group {
                switch page {
                case 0: WelcomePage(tick: tick) { go(1) }
                case 1: ThemePage(tick: tick, back: { go(0) }, next: { go(2) })
                default: ExplainPage(tick: tick, back: { go(1) }, start: finish)
                }
            }
            .id(page)
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
        }
        .tint(theme.ink)
        .sensoryFeedback(.selection, trigger: page)
        .onReceive(NotificationCenter.default.publisher(for: .colorsChanged)) { _ in tick += 1 }
    }

    private func go(_ p: Int) {
        forward = p > page
        withAnimation(.snappy(duration: 0.4)) { page = p }
    }
}

// MARK: Page 1: welcome

private struct WelcomePage: View {
    let tick: Int
    let next: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var bars = 0
    @State private var named = false
    @State private var subtitled = false
    @State private var button = false

    private var theme: AppTheme { _ = tick; return AppTheme(scheme: scheme) }

    var body: some View {
        // The logo and name sit in the exact middle of the screen; the button is pinned to the bottom.
        VStack(spacing: 0) {
            AheadMark(shown: bars, ink: theme.ink, size: 85)
            VStack(spacing: 2) {
                Text("Ahead")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(theme.ink)
                    .opacity(named ? 1 : 0)
                    .offset(y: named ? 0 : 10)
                Text("Your next days at a glance")
                    .font(.system(size: 22, weight: .thin))
                    .foregroundStyle(theme.ink)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
                    .opacity(subtitled ? 1 : 0)
            }
            .padding(.top, 80)
        }
        .offset(y: -70)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
            PillButton(title: "Get started", tick: tick, action: next)
                .opacity(button ? 1 : 0)
                .padding(.bottom, 28)
        }
        .padding(.horizontal, 24)
        .task {
            for i in 1...4 {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) { bars = i }
                try? await Task.sleep(for: .milliseconds(190))
            }
            try? await Task.sleep(for: .milliseconds(350))
            withAnimation(.easeOut(duration: 1.6)) { named = true }
            try? await Task.sleep(for: .milliseconds(1400))
            withAnimation(.easeOut(duration: 1.6)) { subtitled = true }
            try? await Task.sleep(for: .milliseconds(1500))
            withAnimation(.easeOut(duration: 0.5)) { button = true }
        }
    }
}

// MARK: Page 2: choose a theme

/// Pick the look you like. It is yours for free; the other themes come with Ahead Plus.
private struct ThemePage: View {
    let tick: Int
    let back: () -> Void
    let next: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var chosen = SharedSettings.freeThemeID ?? "graphite"

    private var theme: AppTheme { _ = tick; return AppTheme(scheme: scheme) }
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Choose your theme")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 70)
            Text("Yours to keep for free. The other themes come with Ahead Plus.")
                .font(.system(size: 14))
                .foregroundStyle(theme.ink.opacity(0.5))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)
                .padding(.bottom, 22)

            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(LookPreset.all) { p in card(p) }
                }
                .padding(.bottom, 8)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)

            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(theme.card, in: Circle())
                        .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                PillButton(title: "Next", tick: tick, action: next)
            }
            .padding(.vertical, 12)
        }
        .padding(.horizontal, 24)
        .onAppear { select(chosen) }     // the default theme is saved even if you just tap Next
    }

    private func select(_ id: String) {
        guard let p = LookPreset.find(id) else { return }
        chosen = id
        SharedSettings.applyPreset(id: id, light: p.lightSet, dark: p.darkSet)
        SharedSettings.freeThemeID = id
        NotificationCenter.default.post(name: .colorsChanged, object: nil)
        SharedSettings.reloadWidgets()
    }

    private func card(_ p: LookPreset) -> some View {
        let c = scheme == .dark ? p.dark : p.light
        let selected = chosen == p.id
        return Button { select(p.id) } label: {
            VStack(spacing: 8) {
                // a tiny sample of the look: the icon's bars and the accent dot
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(c.background.color)
                    VStack(alignment: .leading, spacing: 5) {
                        Capsule().fill(c.ink.color).frame(width: 44, height: 8)
                        Capsule().fill(c.ink.color.opacity(0.4)).frame(width: 36, height: 5)
                        Capsule().fill(c.ink.color.opacity(0.4)).frame(width: 36, height: 5)
                        Capsule().fill(c.ink.color.opacity(0.4)).frame(width: 22, height: 5)
                    }
                    .padding(14)
                    Circle().fill(p.accent.color).frame(width: 14, height: 14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(12)
                }
                .frame(height: 84)
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(theme.ink.opacity(0.12), lineWidth: 1))
                HStack(spacing: 6) {
                    Text(p.name).font(.system(size: 14, weight: .medium))
                    if selected { Image(systemName: "checkmark.circle.fill").font(.system(size: 14)) }
                }
                .foregroundStyle(theme.ink)
            }
            .padding(10)
            .background(theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? theme.accent : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: Page 2: what the app does

private struct ExplainPage: View {
    let tick: Int
    let back: () -> Void
    let start: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var shown = 0

    private var theme: AppTheme { _ = tick; return AppTheme(scheme: scheme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("How Ahead works")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(theme.ink)
                .padding(.top, 70)
            Text("Three things to know.")
                .font(.system(size: 14))
                .foregroundStyle(theme.ink.opacity(0.5))
                .padding(.top, 6)
                .padding(.bottom, 26)

            VStack(spacing: 14) {
                card(0, symbol: "calendar",
                     title: "A minimal app that links your Apple Calendar with the widgets",
                     note: nil)
                card(1, symbol: "calendar.badge.checkmark",
                     title: "The app needs full calendar access to show your events",
                     note: "No information goes up to the cloud. Everything stays on your device.",
                     noteSymbol: "lock.fill")
                card(2, symbol: "location",
                     title: "The app needs location enabled for the app and widgets to show the weather",
                     note: "No data is being collected.",
                     noteSymbol: "checkmark.shield.fill")
            }
            Spacer(minLength: 0)

            HStack {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 14, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(theme.card, in: Circle())
                        .foregroundStyle(theme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back")
                Spacer()
                PillButton(title: "Start", tick: tick, action: start)
            }
            .padding(.bottom, 12)
        }
        .padding(.horizontal, 24)
        .task {
            for i in 1...3 {
                try? await Task.sleep(for: .milliseconds(i == 1 ? 250 : 180))
                withAnimation(.easeOut(duration: 0.5)) { shown = i }
            }
        }
    }

    private func card(_ index: Int, symbol: String, title: String, note: String?, noteSymbol: String = "") -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .medium))
                .foregroundStyle(theme.ink)
                .frame(width: 46, height: 46)
                .background(theme.ink.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if let note {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: noteSymbol).font(.system(size: 11))
                        Text(note).font(.system(size: 13, weight: .medium))
                    }
                    .foregroundStyle(theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .opacity(shown > index ? 1 : 0)
        .offset(y: shown > index ? 0 : 14)
    }
}

// MARK: Pieces

/// A small, quiet capsule with an arrow: the main button on each page.
struct PillButton: View {
    let title: String
    var tick: Int = 0
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let theme = AppTheme(scheme: scheme)
        let _ = tick
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
            }
            .padding(.horizontal, 20)
            .frame(height: 42)
            .background(theme.card, in: Capsule())
            .overlay(Capsule().strokeBorder(theme.ink.opacity(0.08), lineWidth: 1))
            .foregroundStyle(theme.ink)
        }
        .buttonStyle(.plain)
    }
}

/// The app icon's mark: one bright bar over three softer ones. Each bar slides out from the left
/// as `shown` goes up from 0 to 4.
struct AheadMark: View {
    let shown: Int
    let ink: Color
    var size: CGFloat = 100

    var body: some View {
        // proportions taken from the 1024 px icon (597 px wide mark)
        let s = Double(size) / 597.0
        let bars: [(y: Double, w: Double, h: Double)] = [(0, 597, 96), (152, 516, 54), (260, 516, 54), (368, 330, 54)]
        ZStack(alignment: .topLeading) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(i == 0 ? ink : ink.opacity(0.45))
                    .frame(width: bars[i].w * s, height: bars[i].h * s)
                    .scaleEffect(x: shown > i ? 1 : 0.001, anchor: .leading)
                    .opacity(shown > i ? 1 : 0)
                    .offset(y: bars[i].y * s)
            }
        }
        .frame(width: size, height: 422 * s, alignment: .topLeading)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
