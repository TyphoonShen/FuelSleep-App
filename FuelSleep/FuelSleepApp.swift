import SwiftUI
import SwiftData

@main
struct FuelSleepApp: App {
    @State private var health = HealthStore()

    init() {
        TrainingDays.migrate()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(health)
        }
        .modelContainer(for: [Meal.self, FavoriteMeal.self])
    }
}

struct ContentView: View {
    @Environment(HealthStore.self) private var health
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(ThemeChoice.key) private var themeChoice = ThemeChoice.automatic.rawValue

    private var theme: AppTheme {
        (ThemeChoice(rawValue: themeChoice) ?? .automatic).resolved()
    }

    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
            MealsView()
                .tabItem { Label("Meals", systemImage: "fork.knife") }
            HistoryView()
                .tabItem { Label("History", systemImage: "calendar") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environment(\.theme, theme)
        .tint(theme.accent)
        .preferredColorScheme(theme.colorScheme)
        .task {
            // Only shows the Health permission sheet the first time.
            await health.requestAuthorization()
            AppIconSwitcher.apply(theme)
        }
        .onChange(of: theme.id) { _, _ in
            AppIconSwitcher.apply(theme)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                AppIconSwitcher.apply(theme)
                Task { await health.refresh() }
            }
        }
    }
}
