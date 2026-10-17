import Foundation
import SwiftData

/// One logged meal or snack, stored on the phone with SwiftData.
@Model
final class Meal {
    var id: UUID
    var date: Date
    var name: String
    var calories: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var notes: String
    @Attribute(.externalStorage) var photo: Data?

    init(date: Date = .now,
         name: String,
         calories: Double,
         protein: Double,
         carbs: Double,
         fat: Double,
         notes: String = "",
         photo: Data? = nil) {
        self.id = UUID()
        self.date = date
        self.name = name
        self.calories = calories
        self.protein = protein
        self.carbs = carbs
        self.fat = fat
        self.notes = notes
        self.photo = photo
    }

    var macros: Macros {
        Macros(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }
}

/// Plain value type for nutrition totals and targets.
struct Macros {
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0

    static func + (lhs: Macros, rhs: Macros) -> Macros {
        Macros(calories: lhs.calories + rhs.calories,
               protein: lhs.protein + rhs.protein,
               carbs: lhs.carbs + rhs.carbs,
               fat: lhs.fat + rhs.fat)
    }

    static func total(of meals: [Meal]) -> Macros {
        meals.reduce(Macros()) { $0 + $1.macros }
    }
}

/// A saved meal you can log again with one tap.
@Model
final class FavoriteMeal {
    var id: UUID = UUID()
    var name: String = ""
    var calories: Double = 0
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    @Attribute(.externalStorage) var photo: Data?
    var createdAt: Date = Date.now
    var timesLogged: Int = 0
    var lastLogged: Date?

    init(name: String, macros: Macros, photo: Data? = nil) {
        self.id = UUID()
        self.name = name
        self.calories = macros.calories
        self.protein = macros.protein
        self.carbs = macros.carbs
        self.fat = macros.fat
        self.photo = photo
        self.createdAt = .now
    }

    var macros: Macros {
        Macros(calories: calories, protein: protein, carbs: carbs, fat: fat)
    }

    var draft: MealDraft {
        MealDraft(name: name, macros: macros, photo: photo)
    }
}

/// The parts of a meal needed to log it again (from a favourite or a past meal).
struct MealDraft {
    var name: String
    var macros: Macros
    var photo: Data?
}

extension Meal {
    var draft: MealDraft {
        MealDraft(name: name, macros: macros, photo: photo)
    }
}

extension String {
    /// Used to match meals by name: "Chicken & Rice " == "chicken & rice".
    var mealKey: String {
        trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
