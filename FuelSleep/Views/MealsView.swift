import SwiftUI
import SwiftData
import PhotosUI

/// What the add-meal sheet starts from: a photo, or nothing (manual entry).
struct PendingMeal: Identifiable {
    let id = UUID()
    let image: UIImage?
}

struct MealsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(HealthStore.self) private var health
    @Query(sort: \Meal.date, order: .reverse) private var meals: [Meal]
    @Query private var favorites: [FavoriteMeal]

    @State private var pending: PendingMeal?
    @State private var showCamera = false
    @State private var showLibrary = false
    @State private var pickedItem: PhotosPickerItem?
    @State private var editing: Meal?
    @State private var adjusting: DraftSheet?
    @State private var showQuick = false
    @State private var lastLogged: Meal?

    private var favoriteKeys: Set<String> {
        Set(favorites.map { $0.name.mealKey })
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let meals: [Meal]
        var id: Date { day }
    }

    private var days: [DayGroup] {
        let grouped = Dictionary(grouping: meals) { Calendar.current.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { DayGroup(day: $0, meals: grouped[$0] ?? []) }
    }

    var body: some View {
        NavigationStack {
            List {
                if meals.isEmpty {
                    ContentUnavailableView("No meals yet",
                                           systemImage: "fork.knife",
                                           description: Text("Tap + to photograph a meal, describe it, or pick a favourite."))
                }
                ForEach(days) { group in
                    Section {
                        ForEach(group.meals) { meal in
                            let isFavorite = favoriteKeys.contains(meal.name.mealKey)
                            Button { editing = meal } label: { MealRow(meal: meal, isFavorite: isFavorite) }
                                .buttonStyle(.plain)
                                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                    Button { Task { await logAgain(meal) } } label: {
                                        Label("Log again", systemImage: "arrow.counterclockwise")
                                    }
                                    .tint(.green)
                                    Button { MealLogger.toggleFavorite(meal.draft, context: modelContext) } label: {
                                        Label(isFavorite ? "Unfavourite" : "Favourite",
                                              systemImage: isFavorite ? "star.slash" : "star.fill")
                                    }
                                    .tint(.yellow)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) { delete(meal) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .contextMenu {
                                    Button { Task { await logAgain(meal) } } label: {
                                        Label("Log again now", systemImage: "arrow.counterclockwise")
                                    }
                                    Button { adjusting = DraftSheet(draft: meal.draft) } label: {
                                        Label("Adjust & log again", systemImage: "slider.horizontal.3")
                                    }
                                    Button { MealLogger.toggleFavorite(meal.draft, context: modelContext) } label: {
                                        Label(isFavorite ? "Remove from favourites" : "Add to favourites",
                                              systemImage: isFavorite ? "star.slash" : "star")
                                    }
                                    Button(role: .destructive) { delete(meal) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    } header: {
                        let total = Macros.total(of: group.meals)
                        HStack {
                            Text(dayTitle(group.day))
                            Spacer()
                            Text("\(Int(total.calories)) kcal · C \(Int(total.carbs))g · P \(Int(total.protein))g")
                        }
                    }
                    .themedRows()
                }
            }
            .themedList()
            .navigationTitle("Meals")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        if UIImagePickerController.isSourceTypeAvailable(.camera) {
                            Button { showCamera = true } label: { Label("Take photo", systemImage: "camera") }
                        }
                        Button { showLibrary = true } label: { Label("Choose photo", systemImage: "photo") }
                        Button { pending = PendingMeal(image: nil) } label: { Label("Describe or type it", systemImage: "text.bubble") }
                        Divider()
                        Button { showQuick = true } label: { Label("Favourites & recent", systemImage: "star") }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                }
            }
            .photosPicker(isPresented: $showLibrary, selection: $pickedItem, matching: .images)
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pending = PendingMeal(image: image)
                    }
                    pickedItem = nil
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { image in
                    showCamera = false
                    if let image {
                        // Give the camera time to close before opening the next sheet.
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                            pending = PendingMeal(image: image)
                        }
                    }
                }
                .ignoresSafeArea()
            }
            .sheet(item: $pending) { p in
                AddMealView(image: p.image)
            }
            .sheet(item: $editing) { meal in
                AddMealView(existing: meal)
            }
            .sheet(item: $adjusting) { item in
                AddMealView(draft: item.draft)
            }
            .sheet(isPresented: $showQuick) { QuickLogView() }
            .overlay(alignment: .bottom) { UndoToast(meal: $lastLogged) }
            .sensoryFeedback(.success, trigger: lastLogged?.id)
        }
    }

    private func delete(_ meal: Meal) {
        if lastLogged?.id == meal.id { lastLogged = nil }
        health.deleteMeal(id: meal.id)
        modelContext.delete(meal)
    }

    /// Logs a copy of a past meal right now.
    private func logAgain(_ meal: Meal) async {
        let copy = await MealLogger.log(meal.draft, context: modelContext, health: health)
        withAnimation { lastLogged = copy }
    }

    private func dayTitle(_ day: Date) -> String {
        if Calendar.current.isDateInToday(day) { return "Today" }
        if Calendar.current.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide).day().month())
    }
}

struct MealRow: View {
    let meal: Meal
    var isFavorite: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            if let data = meal.photo, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 52, height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            } else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color(.tertiarySystemFill))
                    .frame(width: 52, height: 52)
                    .overlay(Image(systemName: "fork.knife").foregroundStyle(.secondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(meal.name).font(.body.weight(.medium)).lineLimit(1)
                    if isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text("\(Int(meal.calories)) kcal · P \(Int(meal.protein)) · C \(Int(meal.carbs)) · F \(Int(meal.fat))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(meal.date.formatted(date: .omitted, time: .shortened))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .contentShape(Rectangle())
    }
}
