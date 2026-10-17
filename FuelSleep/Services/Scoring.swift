import SwiftUI

/// A day's score out of 100, built from three parts.
struct DayScore {
    var sleep: Int?         // nil = no sleep recorded
    var nutrition: Int?     // nil = no meals logged
    var activity: Int?      // nil = no activity data
    var total: Int?         // nil = nothing to score
    var workedOut: Bool
    var sleptWell: Bool
    var ateWell: Bool
    var isPartial: Bool     // today: still in progress
}

/// How the daily score works. Change the numbers here to tune it.
///
/// - Sleep (35%): 100 if you sleep within 15 minutes of your goal, minus 25 points for
///   every extra hour short. 7h on an 8h goal scores 81.
/// - Nutrition (40%): how close you got to each target, using training-day targets on
///   training days. Protein 35%, calories 30%, carbs 25%, fat 10%. Being within 10% of
///   calories and carbs (20% for fat) counts as hitting it. Protein only loses points
///   for being under, and scores 0 at half your target.
/// - Activity (25%): 100 on a training day. On a rest day it's based on steps, with
///   10,000 steps scoring 100.
///
/// Parts with no data are left out and the rest are reweighted, so not logging food
/// doesn't count as a zero.
enum Scoring {
    static let sleepWeight = 0.35
    static let nutritionWeight = 0.40
    static let activityWeight = 0.25
    static let stepGoal = 10_000.0

    /// Thresholds for the three calendar badges.
    static let sleptWellAt = 80
    static let ateWellAt = 75

    static func score(date: Date,
                      health: DayHealth?,
                      meals: [Meal],
                      goals: Goals,
                      manualTraining: Bool,
                      now: Date = .now) -> DayScore {
        let isToday = Calendar.current.isDate(date, inSameDayAs: now)
        let fraction = isToday ? dayFraction(now) : 1

        let workedOut = !(health?.workouts.isEmpty ?? true) || manualTraining

        let sleep = health?.sleep.map { sleepScore(hours: $0.hours, goal: goals.sleepHours) }

        var nutrition: Int?
        if !meals.isEmpty && fraction > 0.1 {
            nutrition = nutritionScore(eaten: Macros.total(of: meals),
                                       targets: goals.targets(isTrainingDay: workedOut),
                                       fraction: fraction)
        }

        var activity: Int?
        if workedOut {
            activity = 100
        } else if let steps = health?.steps, steps > 0 {
            let target = stepGoal * max(fraction, 0.2)
            activity = Int((min(steps / target, 1) * 100).rounded())
        }

        var weighted = 0.0
        var weights = 0.0
        if let sleep { weighted += Double(sleep) * sleepWeight; weights += sleepWeight }
        if let nutrition { weighted += Double(nutrition) * nutritionWeight; weights += nutritionWeight }
        if let activity { weighted += Double(activity) * activityWeight; weights += activityWeight }
        let total = weights > 0 ? Int((weighted / weights).rounded()) : nil

        return DayScore(sleep: sleep,
                        nutrition: nutrition,
                        activity: activity,
                        total: total,
                        workedOut: workedOut,
                        sleptWell: (sleep ?? 0) >= sleptWellAt,
                        ateWell: (nutrition ?? 0) >= ateWellAt,
                        isPartial: isToday)
    }

    // MARK: Parts

    static func sleepScore(hours: Double, goal: Double) -> Int {
        let shortBy = goal - hours
        if shortBy <= 0.25 { return 100 }
        return max(0, Int((100 - (shortBy - 0.25) * 25).rounded()))
    }

    /// `fraction` is how much of the day has passed (1 for past days). Today you're judged
    /// against the share of your targets you'd expect to have eaten by now, and you only
    /// lose points for going over once you pass the full day's target.
    static func nutritionScore(eaten: Macros, targets: Macros, fraction: Double) -> Int {
        func part(_ actual: Double, _ full: Double, tolerance: Double) -> Double {
            guard full > 0 else { return 1 }
            if actual > full { return closeness(actual, full, tolerance) }
            let soFar = full * fraction
            if actual >= soFar { return 1 }
            return closeness(actual, soFar, tolerance)
        }

        let calories = part(eaten.calories, targets.calories, tolerance: 0.10)
        let carbs = part(eaten.carbs, targets.carbs, tolerance: 0.10)
        let fat = part(eaten.fat, targets.fat, tolerance: 0.20)
        let proteinTarget = targets.protein * fraction * 0.95
        // Full marks at target; drops to 0 at half the target.
        let ratio = proteinTarget > 0 ? eaten.protein / proteinTarget : 1
        let protein = ratio >= 1 ? 1 : max(0, (ratio - 0.5) / 0.5)

        let total = protein * 0.35 + calories * 0.30 + carbs * 0.25 + fat * 0.10
        return Int((total * 100).rounded())
    }

    /// 1 when within `tolerance` of the target, falling to 0 at 35% beyond that.
    static func closeness(_ actual: Double, _ target: Double, _ tolerance: Double) -> Double {
        guard target > 0 else { return 1 }
        let off = abs(actual - target) / target
        if off <= tolerance { return 1 }
        return max(0, 1 - (off - tolerance) / 0.35)
    }

    /// Share of the eating day (7am–9pm) that has passed.
    static func dayFraction(_ now: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(c.hour ?? 12) + Double(c.minute ?? 0) / 60
        return min(max((hour - 7) / 14, 0), 1)
    }

    // MARK: Display

    static func color(_ score: Int?) -> Color {
        guard let score else { return .gray }
        switch score {
        case 85...: return .green
        case 70..<85: return .blue
        case 50..<70: return .orange
        default: return .red
        }
    }

    static func label(_ score: Int?) -> String {
        guard let score else { return "No data" }
        switch score {
        case 85...: return "Great"
        case 70..<85: return "Good"
        case 50..<70: return "Fair"
        default: return "Poor"
        }
    }
}
