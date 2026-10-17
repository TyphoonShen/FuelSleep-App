import SwiftUI
import SwiftData

// MARK: - Helpers

/// A meal you could log again, from a favourite or from your recent history.
struct QuickItem: Identifiable {
    let id: String
    let draft: MealDraft
    var subtitle: String? = nil
}

/// Wraps a draft so it can drive a sheet.
struct DraftSheet: Identifiable {
    let id = UUID()
    let draft: MealDraft
}

struct RecentMeal: Identifiable {
    let meal: Meal
    let count: Int
    var id: UUID { meal.id }
}

enum RecentMeals {
    /// Meals you've logged in the last `days` days that aren't favourites, most frequent first.
    /// Returns the latest copy of each, so the numbers are what you last used.
    static func list(from meals: [Meal], excluding favoriteKeys: Set<String>,
                     days: Int = 30, limit: Int = 12) -> [RecentMeal] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: .now) ?? .distantPast
        let recent = meals.filter { $0.date >= cutoff && !favoriteKeys.contains($0.name.mealKey) }
        let groups = Dictionary(grouping: recent) { $0.name.mealKey }
        let latest: [RecentMeal] = groups.values.compactMap { group in
            guard let newest = group.max(by: { $0.date < $1.date }) else { return nil }
            return RecentMeal(meal: newest, count: group.count)
        }
        let sorted = latest.sorted { a, b in
            a.count != b.count ? a.count > b.count : a.meal.date > b.meal.date
        }
        return Array(sorted.prefix(limit))
    }
}

/// Small rounded photo, or a fork if there's no photo.
struct MealThumb: View {
    let photo: Data?
    var size: CGFloat = 52

    var body: some View {
        if let photo, let image = UIImage(data: photo) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        } else {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(Color(.tertiarySystemFill))
                .frame(width: size, height: size)
                .overlay(Image(systemName: "fork.knife").font(.system(size: size * 0.35)).foregroundStyle(.secondary))
        }
    }
}

// MARK: - Undo pop-up

/// "Logged Porridge · Undo" bar that slides up after a quick log and disappears after 4 seconds.
struct UndoToast: View {
    @Binding var meal: Meal?
    @Environment(\.modelContext) private var context
    @Environment(HealthStore.self) private var health
    @Environment(\.theme) private var theme

    var body: some View {
        if let meal {
            let name = meal.name
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.great)
                Text("Logged \(name)")
                    .lineLimit(1)
                Spacer(minLength: 8)
                Button("Undo") {
                    withAnimation { self.meal = nil }
                    MealLogger.undo(meal, context: context, health: health)
                }
                .fontWeight(.semibold)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(.regularMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .padding(.horizontal)
            .padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .task(id: meal.id) {
                try? await Task.sleep(for: .seconds(4))
                if !Task.isCancelled {
                    withAnimation { self.meal = nil }
                }
            }
        }
    }
}

// MARK: - Quick add card (Today tab)

struct QuickAddCard: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthStore.self) private var health
    @Environment(\.theme) private var theme

    @Query(sort: [SortDescriptor(\FavoriteMeal.timesLogged, order: .reverse),
                  SortDescriptor(\FavoriteMeal.createdAt)])
    private var favorites: [FavoriteMeal]
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]

    @Binding var lastLogged: Meal?
    @State private var showAll = false
    @State private var describing = false

    private var items: [QuickItem] {
        if !favorites.isEmpty {
            return favorites.prefix(10).map {
                QuickItem(id: "f-\($0.id.uuidString)", draft: $0.draft)
            }
        }
        return RecentMeals.list(from: meals, excluding: [], limit: 6).map {
            QuickItem(id: "r-\($0.meal.id.uuidString)", draft: $0.meal.draft)
        }
    }

    var body: some View {
        Card(title: "Quick add", icon: "bolt.fill") {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { describing = true } label: {
                        chip {
                            Image(systemName: "text.bubble.fill")
                                .font(.title3)
                                .foregroundStyle(theme.accent)
                                .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Describe").font(.subheadline.weight(.semibold))
                                Text("type or say it").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    ForEach(items) { item in
                        Button {
                            Task { await log(item.draft) }
                        } label: {
                            chip {
                                MealThumb(photo: item.draft.photo, size: 30)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.draft.name)
                                        .font(.subheadline.weight(.semibold))
                                        .lineLimit(1)
                                    Text("\(Int(item.draft.macros.calories)) kcal · C \(Int(item.draft.macros.carbs))g")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: 150, alignment: .leading)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }

            HStack {
                Text(favorites.isEmpty
                     ? (items.isEmpty ? "Star meals to pin them here." : "Your recent meals. Star one to pin it here.")
                     : "Tap to log now.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Favourites & recent") { showAll = true }
                    .font(.caption.weight(.semibold))
            }
        }
        .sensoryFeedback(.success, trigger: lastLogged?.id)
        .sheet(isPresented: $showAll) { QuickLogView() }
        .sheet(isPresented: $describing) { AddMealView() }
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }

    private func log(_ draft: MealDraft) async {
        let meal = await MealLogger.log(draft, context: context, health: health)
        withAnimation { lastLogged = meal }
    }
}

// MARK: - Favourites & recent (full list)

struct QuickLogView: View {
    @Environment(\.modelContext) private var context
    @Environment(HealthStore.self) private var health
    @Environment(\.dismiss) private var dismiss

    @Query(sort: [SortDescriptor(\FavoriteMeal.timesLogged, order: .reverse),
                  SortDescriptor(\FavoriteMeal.createdAt)])
    private var favorites: [FavoriteMeal]
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]

    @State private var lastLogged: Meal?
    @State private var adjusting: DraftSheet?

    private var recent: [RecentMeal] {
        RecentMeals.list(from: meals, excluding: Set(favorites.map { $0.name.mealKey }))
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if favorites.isEmpty {
                        Text("No favourites yet. Swipe right on a meal in the Meals tab, or turn on \"Save as favourite\" when adding one.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(favorites) { fav in
                        Button { Task { await log(fav.draft) } } label: {
                            row(fav.draft, subtitle: fav.timesLogged > 0 ? "Logged \(fav.timesLogged)×" : nil)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { context.delete(fav) } label: {
                                Label("Remove", systemImage: "star.slash")
                            }
                        }
                        .contextMenu {
                            Button { Task { await log(fav.draft) } } label: { Label("Log now", systemImage: "plus.circle") }
                            Button { adjusting = DraftSheet(draft: fav.draft) } label: {
                                Label("Adjust & log", systemImage: "slider.horizontal.3")
                            }
                            Button(role: .destructive) { context.delete(fav) } label: {
                                Label("Remove from favourites", systemImage: "star.slash")
                            }
                        }
                    }
                } header: {
                    Text("Favourites")
                } footer: {
                    if !favorites.isEmpty {
                        Text("Tap to log now. Long-press to change the portion first.")
                    }
                }
                .themedRows()

                if !recent.isEmpty {
                    Section {
                        ForEach(recent) { item in
                            Button { Task { await log(item.meal.draft) } } label: {
                                row(item.meal.draft, subtitle: item.count > 1 ? "\(item.count)× in the last 30 days" : nil)
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading) {
                                Button {
                                    MealLogger.toggleFavorite(item.meal.draft, context: context)
                                } label: {
                                    Label("Favourite", systemImage: "star.fill")
                                }
                                .tint(.yellow)
                            }
                            .contextMenu {
                                Button { Task { await log(item.meal.draft) } } label: { Label("Log now", systemImage: "plus.circle") }
                                Button { adjusting = DraftSheet(draft: item.meal.draft) } label: {
                                    Label("Adjust & log", systemImage: "slider.horizontal.3")
                                }
                                Button { MealLogger.toggleFavorite(item.meal.draft, context: context) } label: {
                                    Label("Add to favourites", systemImage: "star")
                                }
                            }
                        }
                    } header: {
                        Text("Recent")
                    } footer: {
                        Text("Swipe right to add to favourites.")
                    }
                    .themedRows()
                }
            }
            .themedList()
            .navigationTitle("Quick add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .overlay(alignment: .bottom) { UndoToast(meal: $lastLogged) }
            .sensoryFeedback(.success, trigger: lastLogged?.id)
            .sheet(item: $adjusting) { item in
                AddMealView(draft: item.draft)
            }
        }
    }

    private func row(_ draft: MealDraft, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            MealThumb(photo: draft.photo, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(draft.name).font(.body.weight(.medium)).lineLimit(1)
                Text("\(Int(draft.macros.calories)) kcal · P \(Int(draft.macros.protein)) · C \(Int(draft.macros.carbs)) · F \(Int(draft.macros.fat))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if let subtitle {
                    Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Image(systemName: "plus.circle.fill")
                .font(.title3)
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }

    private func log(_ draft: MealDraft) async {
        let meal = await MealLogger.log(draft, context: context, health: health)
        withAnimation { lastLogged = meal }
    }
}
