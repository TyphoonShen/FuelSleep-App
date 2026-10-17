import SwiftUI
import UIKit

// MARK: - Choosing a theme

/// What you pick in Settings. "Automatic" goes spooky from 15–31 October.
enum ThemeChoice: String, CaseIterable, Identifiable {
    case automatic, classic, halloween

    static let key = "theme.choice"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return "Automatic"
        case .classic: return "Classic"
        case .halloween: return "Halloween 🎃"
        }
    }

    func resolved(on date: Date = .now) -> AppTheme {
        switch self {
        case .classic: return .classic
        case .halloween: return .halloween
        case .automatic:
            let c = Calendar.current.dateComponents([.month, .day], from: date)
            return (c.month == 10 && (c.day ?? 0) >= 15) ? .halloween : .classic
        }
    }
}

// MARK: - Theme definition

/// An icon for the trained / slept well / ate well badges: an SF Symbol or an emoji.
struct ThemeBadge {
    var name: String
    var symbol: String? = nil
    var emoji: String? = nil
}

struct AppTheme {
    let id: String

    // Overall look
    let colorScheme: ColorScheme?      // nil = follow the phone's light/dark setting
    let accent: Color
    let background: Color
    let card: Color

    // Score
    let great: Color
    let good: Color
    let fair: Color
    let poor: Color
    let ringTrack: Color
    let labels: (great: String, good: String, fair: String, poor: String, none: String)
    let pumpkinRing: Bool

    // The three parts of the score
    let sleepColor: Color
    let nutritionColor: Color
    let activityColor: Color
    let trained: ThemeBadge
    let sleptWell: ThemeBadge
    let ateWell: ThemeBadge

    // Detail colours
    let calories: Color
    let protein: Color
    let carbs: Color
    let fat: Color
    let deepSleep: Color
    let coreSleep: Color
    let remSleep: Color
    let awake: Color
    let warn: Color
    let info: Color
    let ok: Color

    // Extras
    let floatingBats: Bool
    let greeting: String?
    let coachTone: String?
    let appIcon: String?               // nil = the main icon

    // Weekly review chart: training vs rest days (checked for colour-blind contrast)
    let chartTraining: Color
    let chartRest: Color

    func scoreColor(_ score: Int?) -> Color {
        guard let score else { return .gray }
        switch score {
        case 85...: return great
        case 70..<85: return good
        case 50..<70: return fair
        default: return poor
        }
    }

    func scoreLabel(_ score: Int?) -> String {
        guard let score else { return labels.none }
        switch score {
        case 85...: return labels.great
        case 70..<85: return labels.good
        case 50..<70: return labels.fair
        default: return labels.poor
        }
    }

    func insightColor(_ level: InsightLevel) -> Color {
        switch level {
        case .good: return ok
        case .info: return info
        case .warn: return warn
        }
    }
}

extension AppTheme {
    static let classic = AppTheme(
        id: "classic",
        colorScheme: nil,
        accent: .accentColor,
        background: Color(.systemGroupedBackground),
        card: Color(.secondarySystemGroupedBackground),
        great: .green, good: .blue, fair: .orange, poor: .red,
        ringTrack: Color(.tertiarySystemFill),
        labels: ("Great", "Good", "Fair", "Poor", "No data"),
        pumpkinRing: false,
        sleepColor: .indigo, nutritionColor: .green, activityColor: .orange,
        trained: ThemeBadge(name: "Trained", symbol: "dumbbell.fill"),
        sleptWell: ThemeBadge(name: "Slept well", symbol: "moon.fill"),
        ateWell: ThemeBadge(name: "Ate well", symbol: "fork.knife"),
        calories: .orange, protein: .red, carbs: .blue, fat: .yellow,
        deepSleep: .indigo, coreSleep: .blue, remSleep: .cyan, awake: .orange,
        warn: .orange, info: .blue, ok: .green,
        floatingBats: false,
        greeting: nil,
        coachTone: nil,
        appIcon: nil,
        chartTraining: .orange,
        chartRest: .blue
    )

    static let halloween = AppTheme(
        id: "halloween",
        colorScheme: .dark,
        accent: Color(hex: 0xFF7A1A),              // pumpkin
        background: Color(hex: 0x120B1E),          // midnight
        card: Color(hex: 0x21142F),                // haunted purple
        great: Color(hex: 0x8BE04E),               // slime green
        good: Color(hex: 0xF5C04A),                // candlelight
        fair: Color(hex: 0xFF7A1A),                // pumpkin
        poor: Color(hex: 0xE5484D),                // blood red
        ringTrack: Color(hex: 0xFF7A1A).opacity(0.18),
        labels: ("Spooktacular", "Wicked good", "Haunted", "Cursed", "Ghosted"),
        pumpkinRing: true,
        sleepColor: Color(hex: 0xA88BFF),
        nutritionColor: Color(hex: 0x8BE04E),
        activityColor: Color(hex: 0xFF8A2A),
        trained: ThemeBadge(name: "Trained", emoji: "🦇"),
        sleptWell: ThemeBadge(name: "Dead asleep", emoji: "⚰️"),
        ateWell: ThemeBadge(name: "Ate well", emoji: "🎃"),
        calories: Color(hex: 0xFF7A1A),
        protein: Color(hex: 0xE5484D),
        carbs: Color(hex: 0xA88BFF),
        fat: Color(hex: 0xF5C04A),
        deepSleep: Color(hex: 0x7B5CE6),
        coreSleep: Color(hex: 0xA88BFF),
        remSleep: Color(hex: 0x8BE04E),
        awake: Color(hex: 0xFF7A1A),
        warn: Color(hex: 0xFF7A1A),
        info: Color(hex: 0xA88BFF),
        ok: Color(hex: 0x8BE04E),
        floatingBats: true,
        greeting: "🕸️ Trick or treat yourself right",
        coachTone: "It's Halloween season: use a light, playful spooky tone with at most one Halloween pun, but keep the advice itself practical and specific.",
        appIcon: "AppIcon-Halloween",
        chartTraining: Color(hex: 0xE06A12),
        chartRest: Color(hex: 0x8A6AE8)
    )
}

// MARK: - Making the theme available to every view

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.classic
}

extension EnvironmentValues {
    var theme: AppTheme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    /// Color(hex: 0xFF7A1A)
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

// MARK: - App icon

enum AppIconSwitcher {
    /// Switches the home-screen icon to match the theme. iOS shows a short pop-up when it changes.
    @MainActor
    static func apply(_ theme: AppTheme) {
        let app = UIApplication.shared
        guard app.supportsAlternateIcons,
              app.alternateIconName != theme.appIcon,
              app.applicationState == .active else { return }
        app.setAlternateIconName(theme.appIcon) { _ in }
    }
}

// MARK: - Themed pieces

/// A badge icon that greys out when not earned.
struct BadgeIcon: View {
    let badge: ThemeBadge
    var on: Bool = true
    var color: Color
    var size: CGFloat = 14

    var body: some View {
        if let emoji = badge.emoji {
            Text(emoji)
                .font(.system(size: size))
                .grayscale(on ? 0 : 1)
                .opacity(on ? 1 : 0.28)
        } else {
            Image(systemName: badge.symbol ?? "circle.fill")
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(on ? color : Color(.quaternaryLabel))
        }
    }
}

/// A few bats drifting across the top of the screen. Stays still if Reduce Motion is on.
struct FloatingBats: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Bat {
        let x: Double, y: Double, size: Double, speed: Double, phase: Double
    }

    private let bats = [
        Bat(x: 0.78, y: 0.30, size: 26, speed: 0.55, phase: 0),
        Bat(x: 0.62, y: 0.62, size: 18, speed: 0.75, phase: 2.1),
        Bat(x: 0.90, y: 0.72, size: 14, speed: 0.95, phase: 4.0)
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
                ZStack {
                    ForEach(bats.indices, id: \.self) { i in
                        let bat = bats[i]
                        Text("🦇")
                            .font(.system(size: bat.size))
                            .scaleEffect(x: 1, y: 0.8 + 0.2 * abs(sin(t * 7 + bat.phase)))
                            .rotationEffect(.degrees(sin(t * bat.speed + bat.phase) * 10))
                            .position(x: (bat.x + sin(t * bat.speed + bat.phase) * 0.07) * geo.size.width,
                                      y: (bat.y + cos(t * bat.speed * 1.4 + bat.phase) * 0.12) * geo.size.height)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Lists and forms

extension View {
    /// Gives a List or Form the theme's background (no change in Classic).
    func themedList() -> some View {
        modifier(ThemedListBackground())
    }

    /// Gives the rows of a list section the theme's card colour.
    func themedRows() -> some View {
        modifier(ThemedRowBackground())
    }
}

private struct ThemedListBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(theme.background)
    }
}

private struct ThemedRowBackground: ViewModifier {
    @Environment(\.theme) private var theme

    func body(content: Content) -> some View {
        content.listRowBackground(theme.card)
    }
}
