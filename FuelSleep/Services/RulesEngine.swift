import Foundation

enum InsightLevel {
    case good, info, warn
}

struct Insight: Identifiable {
    let id = UUID()
    let level: InsightLevel
    let icon: String       // SF Symbol name
    let title: String
    let detail: String
}

/// Everything the rules (and the AI coach) need to know about today.
struct DayContext {
    var goals: Goals
    var eaten: Macros
    var mealCount: Int
    var sleepHours: Double?
    var isTrainingDay: Bool
    var workoutMinutes: Int
    var activeEnergy: Double
    var now: Date = .now

    var targets: Macros { goals.targets(isTrainingDay: isTrainingDay) }

    /// Rough share of the day's food you'd expect to have eaten by now (7am → 9pm).
    var expectedFraction: Double {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: now)
        let hour = Double(comps.hour ?? 12) + Double(comps.minute ?? 0) / 60
        return min(max((hour - 7) / 14, 0), 1)
    }

    var hour: Int { Calendar.current.component(.hour, from: now) }
}

/// Free, offline checks. These always run; the AI coach is an optional extra on top.
enum RulesEngine {
    static func insights(for c: DayContext) -> [Insight] {
        var out: [Insight] = []
        let t = c.targets
        let expected = c.expectedFraction

        // Nothing logged yet
        if c.mealCount == 0 && c.hour >= 11 {
            out.append(Insight(level: .info, icon: "camera",
                               title: "Nothing logged yet today",
                               detail: "Snap a photo of your next meal so the checks below have something to work with."))
        }

        // Carbs on a training day — the main scenario
        if c.isTrainingDay && c.hour >= 12 && c.eaten.carbs < t.carbs * expected * 0.8 {
            let left = max(t.carbs - c.eaten.carbs, 0)
            out.append(Insight(level: .warn, icon: "bolt.fill",
                               title: "Carbs are behind on a training day",
                               detail: "\(g(c.eaten.carbs)) of \(g(t.carbs)) so far, \(g(left)) to go. Carbs refill the glycogen your session used: add rice, oats, potatoes, pasta, bagels or fruit to your next meals."))
        } else if !c.isTrainingDay && c.hour >= 14 && c.eaten.carbs < t.carbs * expected * 0.6 {
            out.append(Insight(level: .info, icon: "leaf",
                               title: "Carbs are on the low side",
                               detail: "\(g(c.eaten.carbs)) of \(g(t.carbs)). Fine on a rest day if it's deliberate; otherwise add some to dinner."))
        }

        // Protein
        if c.hour >= 12 && c.eaten.protein < t.protein * expected * 0.8 {
            let left = max(t.protein - c.eaten.protein, 0)
            out.append(Insight(level: .warn, icon: "figure.strengthtraining.traditional",
                               title: "Protein is behind",
                               detail: "\(g(c.eaten.protein)) of \(g(t.protein)), \(g(left)) to go. Spread it over your next meals: chicken, fish, eggs, Greek yogurt, cottage cheese or a shake (each roughly 25–40g)."))
        } else if c.eaten.protein >= t.protein {
            out.append(Insight(level: .good, icon: "checkmark.seal",
                               title: "Protein target hit",
                               detail: "\(g(c.eaten.protein)) eaten. Nice work."))
        }

        // Calories, judged in the evening
        if c.hour >= 20 && c.mealCount > 0 {
            if c.eaten.calories < t.calories * 0.8 {
                out.append(Insight(level: .warn, icon: "flame",
                                   title: "Under-fuelled today",
                                   detail: "\(kcal(c.eaten.calories)) of \(kcal(t.calories)). A big gap on \(c.isTrainingDay ? "a training day" : "most days") slows recovery; a late snack like yogurt with granola or toast with peanut butter helps."))
            } else if c.eaten.calories > t.calories * 1.15 {
                out.append(Insight(level: .info, icon: "flame",
                                   title: "Over your calorie target",
                                   detail: "\(kcal(c.eaten.calories)) of \(kcal(t.calories)). One day doesn't matter much; look at the weekly trend."))
            }
        }

        // Sleep
        if let hours = c.sleepHours {
            if hours < c.goals.sleepHours - 1 {
                var detail = "\(h(hours)) asleep vs your \(h(c.goals.sleepHours)) goal. Aim for an earlier, consistent bedtime and cut caffeine after 2pm."
                if c.isTrainingDay {
                    detail += " After short sleep, keep training intensity moderate and don't skimp on carbs and water."
                }
                out.append(Insight(level: .warn, icon: "bed.double", title: "Short sleep last night", detail: detail))
            } else if hours >= c.goals.sleepHours - 0.25 {
                out.append(Insight(level: .good, icon: "moon.stars",
                                   title: "Well rested",
                                   detail: "\(h(hours)) asleep. Good day to push in training."))
            }
        } else {
            out.append(Insight(level: .info, icon: "applewatch",
                               title: "No sleep data for last night",
                               detail: "Wear your Apple Watch to bed with Sleep Focus on, or check that Health access is allowed in Settings."))
        }

        if out.allSatisfy({ $0.level == .good }) {
            out.append(Insight(level: .good, icon: "hand.thumbsup",
                               title: "On track",
                               detail: "Nothing needs fixing right now. Keep going."))
        }

        // Warnings first
        return out.sorted { rank($0.level) < rank($1.level) }
    }

    /// Plain-text summary sent to the AI coach.
    static func summary(for c: DayContext, meals: [Meal], workouts: [WorkoutSummary]) -> String {
        let t = c.targets
        let time = c.now.formatted(date: .omitted, time: .shortened)
        var lines: [String] = []
        lines.append("Current time: \(time).")
        lines.append("Training day: \(c.isTrainingDay ? "yes" : "no").")
        if workouts.isEmpty {
            lines.append("Workouts recorded today: none\(c.isTrainingDay ? " (marked as training day manually)" : "").")
        } else {
            for w in workouts {
                let when = w.start.formatted(date: .omitted, time: .shortened)
                let energy = w.energy.map { ", \(Int($0)) kcal" } ?? ""
                lines.append("Workout: \(w.name) at \(when), \(w.minutes) min\(energy).")
            }
        }
        lines.append("Active energy today: \(Int(c.activeEnergy)) kcal.")
        if let s = c.sleepHours {
            lines.append("Sleep last night: \(h(s)) (goal \(h(c.goals.sleepHours))).")
        } else {
            lines.append("Sleep last night: no data.")
        }
        lines.append("Today's targets: \(kcal(t.calories)), protein \(g(t.protein)), carbs \(g(t.carbs)), fat \(g(t.fat)).")
        lines.append("Eaten so far: \(kcal(c.eaten.calories)), protein \(g(c.eaten.protein)), carbs \(g(c.eaten.carbs)), fat \(g(c.eaten.fat)).")
        if meals.isEmpty {
            lines.append("Meals logged: none yet.")
        } else {
            lines.append("Meals logged:")
            for m in meals.sorted(by: { $0.date < $1.date }) {
                let when = m.date.formatted(date: .omitted, time: .shortened)
                lines.append("- \(when) \(m.name): \(Int(m.calories)) kcal, P \(Int(m.protein))g, C \(Int(m.carbs))g, F \(Int(m.fat))g")
            }
        }
        let flags = insights(for: c).filter { $0.level == .warn }.map(\.title)
        if !flags.isEmpty {
            lines.append("Flags from the app's own checks: \(flags.joined(separator: "; ")).")
        }
        lines.append("What should I focus on for the rest of today?")
        return lines.joined(separator: "\n")
    }

    private static func rank(_ l: InsightLevel) -> Int {
        switch l { case .warn: return 0; case .info: return 1; case .good: return 2 }
    }

    private static func g(_ v: Double) -> String { "\(Int(v.rounded()))g" }
    private static func kcal(_ v: Double) -> String { "\(Int(v.rounded())) kcal" }
    private static func h(_ v: Double) -> String {
        let total = Int((v * 60).rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }
}
