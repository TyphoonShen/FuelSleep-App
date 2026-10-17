import Foundation
import SwiftData

/// One place that saves meals, so quick-logging, "log again" and the add-meal form
/// all behave the same (stored on the phone, and written to Apple Health if enabled).
@MainActor
enum MealLogger {
    static var saveToHealth: Bool {
        UserDefaults.standard.object(forKey: "health.saveMeals") as? Bool ?? true
    }

    /// Logs a copy of `draft` at `date` and returns it (so it can be undone).
    @discardableResult
    static func log(_ draft: MealDraft,
                    at date: Date = .now,
                    notes: String = "",
                    context: ModelContext,
                    health: HealthStore) async -> Meal {
        let meal = Meal(date: date,
                        name: draft.name,
                        calories: draft.macros.calories,
                        protein: draft.macros.protein,
                        carbs: draft.macros.carbs,
                        fat: draft.macros.fat,
                        notes: notes,
                        photo: draft.photo)
        context.insert(meal)
        bumpFavorite(named: draft.name, context: context)
        if saveToHealth {
            await health.saveMeal(id: meal.id, name: meal.name, date: date, macros: draft.macros)
        }
        return meal
    }

    static func undo(_ meal: Meal, context: ModelContext, health: HealthStore) {
        health.deleteMeal(id: meal.id)
        context.delete(meal)
    }

    // MARK: Favourites

    static func favorite(named name: String, context: ModelContext) -> FavoriteMeal? {
        let key = name.mealKey
        let all = (try? context.fetch(FetchDescriptor<FavoriteMeal>())) ?? []
        return all.first { $0.name.mealKey == key }
    }

    /// Adds the meal to favourites, or removes it if it's already there.
    static func toggleFavorite(_ draft: MealDraft, context: ModelContext) {
        if let existing = favorite(named: draft.name, context: context) {
            context.delete(existing)
        } else {
            context.insert(FavoriteMeal(name: draft.name, macros: draft.macros, photo: draft.photo))
        }
    }

    /// Keeps favourites sorted by how often you actually eat them.
    private static func bumpFavorite(named name: String, context: ModelContext) {
        guard let fav = favorite(named: name, context: context) else { return }
        fav.timesLogged += 1
        fav.lastLogged = .now
    }
}
