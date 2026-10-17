import Foundation

/// Everything about one day that the weekly review needs.
struct DayStat: Identifiable {
    let date: Date
    let score: DayScore
    let health: DayHealth?
    let eaten: Macros
    let mealCount: Int
    let targets: Macros
    let isComplete: Bool        // the day is over (today isn't)

    var id: Date { date }
    var isTraining: Bool { score.workedOut }
    var sleepHours: Double? { health?.sleep?.hours }
    var hasMeals: Bool { mealCount > 0 }

    /// Carbs eaten as a % of the day's carb target.
    var carbPercent: Int? {
        guard hasMeals, targets.carbs > 0 else { return nil }
        return Int((eaten.carbs / targets.carbs * 100).rounded())
    }
}

/// How often a macro target was hit, on days with meals logged.
struct MacroHit: Identifiable {
    let name: String
    let hit: Int
    let of: Int
    var id: String { name }
    var rate: Double { of > 0 ? Double(hit) / Double(of) : 0 }
}

/// One week (Monday–Sunday in the UK) of days, with the numbers the review shows.
struct WeekStats {
    let start: Date
    let days: [DayStat]         // only days that have started

    var end: Date { Calendar.current.date(byAdding: .day, value: 7, to: start) ?? start }
    var complete: [DayStat] { days.filter(\.isComplete) }

    /// Averages use finished days; early in the week (nothing finished yet) they use today.
    private var counted: [DayStat] { complete.isEmpty ? days : complete }

    var averageScore: Int? {
        let totals = counted.compactMap(\.score.total)
        guard !totals.isEmpty else { return nil }
        return Int((Double(totals.reduce(0, +)) / Double(totals.count)).rounded())
    }

    var trainedDays: Int { days.filter(\.isTraining).count }
    var sleptWellNights: Int { days.filter(\.score.sleptWell).count }
    var ateWellDays: Int { complete.filter(\.score.ateWell).count }
    var loggedDays: Int { complete.filter(\.hasMeals).count }

    var averageSleep: Double? {
        let hours = days.compactMap(\.sleepHours)
        guard !hours.isEmpty else { return nil }
        return hours.reduce(0, +) / Double(hours.count)
    }

    /// Hitting a target uses the same tolerances as the daily score.
    var macroHits: [MacroHit] {
        let logged = complete.filter(\.hasMeals)
        func count(_ ok: (DayStat) -> Bool) -> Int { logged.filter(ok).count }
        return [
            MacroHit(name: "Calories", hit: count { Scoring.closeness($0.eaten.calories, $0.targets.calories, 0.10) == 1 }, of: logged.count),
            MacroHit(name: "Protein", hit: count { $0.eaten.protein >= $0.targets.protein * 0.95 }, of: logged.count),
            MacroHit(name: "Carbs", hit: count { Scoring.closeness($0.eaten.carbs, $0.targets.carbs, 0.10) == 1 }, of: logged.count),
            MacroHit(name: "Fat", hit: count { Scoring.closeness($0.eaten.fat, $0.targets.fat, 0.20) == 1 }, of: logged.count)
        ]
    }

    /// Average % of the carb target eaten on training days (true) or rest days (false).
    func averageCarbPercent(training: Bool) -> Int? {
        let values = complete.filter { $0.isTraining == training }.compactMap(\.carbPercent)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    // MARK: Building

    static func build(start: Date,
                      healthByDay: [Date: DayHealth],
                      meals: [Meal],
                      goals: Goals,
                      manualDates: String,
                      now: Date = .now) -> WeekStats {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let mealsByDay = Dictionary(grouping: meals) { cal.startOfDay(for: $0.date) }

        var days: [DayStat] = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: start), day <= now else { continue }
            let dayMeals = mealsByDay[day] ?? []
            let score = Scoring.score(date: day,
                                      health: healthByDay[day],
                                      meals: dayMeals,
                                      goals: goals,
                                      manualTraining: TrainingDays.contains(manualDates, day),
                                      now: now)
            days.append(DayStat(date: day,
                                score: score,
                                health: healthByDay[day],
                                eaten: Macros.total(of: dayMeals),
                                mealCount: dayMeals.count,
                                targets: goals.targets(isTrainingDay: score.workedOut),
                                isComplete: day < today))
        }
        return WeekStats(start: start, days: days)
    }

    // MARK: Text for the AI review

    func summary(previousAverage: Int?, goals: Goals) -> String {
        let lastDay = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        var lines: [String] = []
        lines.append("Week: \(start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))) to \(lastDay.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))). Finished days so far: \(complete.count) of 7.")
        let base = goals.base
        let training = goals.targets(isTrainingDay: true)
        lines.append("Targets: rest days \(Int(base.calories)) kcal, P \(Int(base.protein))g, C \(Int(base.carbs))g, F \(Int(base.fat))g; training days \(Int(training.calories)) kcal, C \(Int(training.carbs))g. Sleep goal \(fmtHours(goals.sleepHours)).")
        lines.append("Daily scores are out of 100 (sleep 35%, nutrition 40%, activity 25%).")
        lines.append("")
        lines.append("Day by day:")
        for d in days {
            var parts: [String] = [d.date.formatted(.dateTime.weekday(.abbreviated).day())]
            if !d.isComplete { parts.append("(today, in progress)") }
            parts.append("score \(d.score.total.map { "\($0)" } ?? "n/a")")
            parts.append("sleep \(d.sleepHours.map { fmtHours($0) } ?? "no data")")
            if let workouts = d.health?.workouts, !workouts.isEmpty {
                parts.append("trained: " + workouts.map { "\($0.name) \($0.minutes)min" }.joined(separator: ", "))
            } else if d.isTraining {
                parts.append("trained (not recorded)")
            } else {
                parts.append("rest day, \(Int(d.health?.steps ?? 0)) steps")
            }
            if d.hasMeals {
                parts.append("ate \(Int(d.eaten.calories))/\(Int(d.targets.calories)) kcal, P \(Int(d.eaten.protein))/\(Int(d.targets.protein))g, C \(Int(d.eaten.carbs))/\(Int(d.targets.carbs))g, F \(Int(d.eaten.fat))/\(Int(d.targets.fat))g (\(d.mealCount) meals)")
            } else {
                parts.append("no meals logged")
            }
            lines.append("- " + parts.joined(separator: "; "))
        }
        lines.append("")
        lines.append("Week average score: \(averageScore.map { "\($0)" } ?? "n/a"); previous week: \(previousAverage.map { "\($0)" } ?? "n/a").")
        lines.append("Trained \(trainedDays) days; slept well \(sleptWellNights) nights; ate well \(ateWellDays) days; meals logged on \(loggedDays) of \(complete.count) finished days.")
        if let s = averageSleep { lines.append("Average sleep: \(fmtHours(s)).") }
        lines.append("Target hit rates: " + macroHits.map { "\($0.name) \($0.hit)/\($0.of)" }.joined(separator: ", ") + ".")
        if let t = averageCarbPercent(training: true) { lines.append("Carbs on training days: \(t)% of target on average.") }
        if let r = averageCarbPercent(training: false) { lines.append("Carbs on rest days: \(r)% of target on average.") }
        return lines.joined(separator: "\n")
    }

    private func fmtHours(_ h: Double) -> String {
        let m = Int((h * 60).rounded())
        return "\(m / 60)h \(String(format: "%02d", m % 60))m"
    }
}

extension Calendar {
    /// Start of the week containing `date` (Monday in the UK).
    func startOfWeek(for date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }
}

// MARK: - Saved AI reviews

struct WeeklyReview: Codable {
    var headline: String
    var wentWell: [String]
    var focus: String
    var plan: [String]
    var generatedAt: Date?
}

/// Keeps one AI review per week on the phone, so opening the screen again costs nothing.
enum WeeklyReviewStore {
    private static func key(_ start: Date) -> String { "weeklyReview.\(start.dayKey)" }

    static func load(for start: Date) -> WeeklyReview? {
        guard let data = UserDefaults.standard.data(forKey: key(start)) else { return nil }
        return try? JSONDecoder().decode(WeeklyReview.self, from: data)
    }

    static func save(_ review: WeeklyReview, for start: Date) {
        if let data = try? JSONEncoder().encode(review) {
            UserDefaults.standard.set(data, forKey: key(start))
        }
    }
}
