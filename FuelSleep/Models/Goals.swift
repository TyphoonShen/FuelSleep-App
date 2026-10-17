import Foundation

/// UserDefaults keys and default values for your targets.
/// Views read these with @AppStorage, so changing them in Settings updates everything.
enum GoalKey {
    static let calories = "goal.calories"
    static let protein = "goal.protein"
    static let carbs = "goal.carbs"
    static let fat = "goal.fat"
    static let sleepHours = "goal.sleepHours"
    static let trainingCarbBoost = "goal.trainingCarbBoost"
    static let manualTrainingDate = "training.manualDate"      // old: one day only
    static let manualTrainingDates = "training.manualDates"    // comma-separated day keys
}

/// Days you marked "I trained" by hand (workouts not recorded on the Watch).
/// Stored as "2026-10-12,2026-10-14" so it works with @AppStorage.
enum TrainingDays {
    static func contains(_ stored: String, _ date: Date) -> Bool {
        stored.split(separator: ",").contains(Substring(date.dayKey))
    }

    static func setting(_ stored: String, _ date: Date, trained: Bool) -> String {
        var keys = Set(stored.split(separator: ",").map(String.init))
        if trained { keys.insert(date.dayKey) } else { keys.remove(date.dayKey) }
        return keys.sorted().joined(separator: ",")
    }

    /// Moves the old single-day flag into the new list (runs once at launch).
    static func migrate() {
        let d = UserDefaults.standard
        guard let old = d.string(forKey: GoalKey.manualTrainingDate), !old.isEmpty else { return }
        let current = d.string(forKey: GoalKey.manualTrainingDates) ?? ""
        var keys = Set(current.split(separator: ",").map(String.init))
        keys.insert(old)
        d.set(keys.sorted().joined(separator: ","), forKey: GoalKey.manualTrainingDates)
        d.removeObject(forKey: GoalKey.manualTrainingDate)
    }
}

enum GoalDefault {
    static let calories: Double = 2500
    static let protein: Double = 150
    static let carbs: Double = 280
    static let fat: Double = 80
    static let sleepHours: Double = 8
    /// Extra grams of carbs added to the target on a day you train.
    static let trainingCarbBoost: Double = 60
}

struct Goals {
    var base: Macros
    var sleepHours: Double
    var trainingCarbBoost: Double

    /// Targets for today, bumped up on training days.
    func targets(isTrainingDay: Bool) -> Macros {
        guard isTrainingDay else { return base }
        var t = base
        t.carbs += trainingCarbBoost
        t.calories += trainingCarbBoost * 4   // 4 kcal per gram of carbohydrate
        return t
    }
}

extension Date {
    /// "2026-10-11" style key for per-day flags.
    var dayKey: String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }
}
