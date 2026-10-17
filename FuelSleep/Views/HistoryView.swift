import SwiftUI
import SwiftData

/// Month calendar: each day shows its score ring and three badges
/// (trained, slept well, ate well). Tap a day for the full breakdown.
struct HistoryView: View {
    @Environment(HealthStore.self) private var health
    @Environment(\.theme) private var theme
    @Query(sort: \Meal.date) private var meals: [Meal]

    @AppStorage(GoalKey.calories) private var calGoal = GoalDefault.calories
    @AppStorage(GoalKey.protein) private var proteinGoal = GoalDefault.protein
    @AppStorage(GoalKey.carbs) private var carbGoal = GoalDefault.carbs
    @AppStorage(GoalKey.fat) private var fatGoal = GoalDefault.fat
    @AppStorage(GoalKey.sleepHours) private var sleepGoal = GoalDefault.sleepHours
    @AppStorage(GoalKey.trainingCarbBoost) private var carbBoost = GoalDefault.trainingCarbBoost
    @AppStorage(GoalKey.manualTrainingDates) private var manualDates = ""

    @State private var month = Calendar.current.startOfMonth(for: .now)
    @State private var healthByDay: [Date: DayHealth] = [:]
    @State private var loading = false
    @State private var selected: SelectedDay?

    private let cal = Calendar.current

    private var goals: Goals {
        Goals(base: Macros(calories: calGoal, protein: proteinGoal, carbs: carbGoal, fat: fatGoal),
              sleepHours: sleepGoal,
              trainingCarbBoost: carbBoost)
    }

    private var mealsByDay: [Date: [Meal]] {
        Dictionary(grouping: meals) { cal.startOfDay(for: $0.date) }
    }

    private var isCurrentMonth: Bool {
        cal.isDate(month, equalTo: .now, toGranularity: .month)
    }

    var body: some View {
        let mealsByDay = self.mealsByDay
        let days = cal.daysInMonth(month)
        let scores = Dictionary(uniqueKeysWithValues: days.filter { $0 <= .now }.map { day in
            (day, score(for: day, mealsByDay: mealsByDay))
        })

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    WeeklyReviewLink()
                    monthHeader
                    summary(scores: Array(scores.values))
                    Card(title: "Calendar", icon: "calendar") {
                        grid(days: days, scores: scores)
                        legend
                    }
                    Text("Scores use your current targets from Settings. Tap a day for the breakdown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle("History")
            .refreshable { await load() }
            .task(id: month) { await load() }
            .sheet(item: $selected) { sel in
                DayDetailView(date: sel.date,
                              health: healthByDay[sel.date],
                              meals: mealsByDay[sel.date] ?? [],
                              goals: goals)
            }
        }
    }

    // MARK: Pieces

    private var monthHeader: some View {
        HStack {
            Button {
                month = cal.date(byAdding: .month, value: -1, to: month) ?? month
            } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Spacer()
            HStack(spacing: 8) {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                if loading { ProgressView().controlSize(.small) }
            }
            Spacer()
            Button {
                month = cal.date(byAdding: .month, value: 1, to: month) ?? month
            } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
            .disabled(isCurrentMonth)
        }
        .padding(.horizontal, 4)
    }

    private func summary(scores: [DayScore]) -> some View {
        let totals = scores.compactMap(\.total)
        let average = totals.isEmpty ? nil : Int((Double(totals.reduce(0, +)) / Double(totals.count)).rounded())
        return Card(title: "This month", icon: "chart.bar.xaxis") {
            HStack(spacing: 16) {
                VStack(spacing: 4) {
                    ScoreRing(score: average, size: 64, lineWidth: 7)
                    Text("Average").font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 8) {
                    stat(theme.trained, theme.activityColor, scores.filter(\.workedOut).count, "days trained")
                    stat(theme.sleptWell, theme.sleepColor, scores.filter(\.sleptWell).count,
                         theme.pumpkinRing ? "nights dead asleep" : "nights slept well")
                    stat(theme.ateWell, theme.nutritionColor, scores.filter(\.ateWell).count, "days ate well")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func stat(_ badge: ThemeBadge, _ color: Color, _ count: Int, _ label: String) -> some View {
        HStack(spacing: 8) {
            BadgeIcon(badge: badge, color: color, size: 15).frame(width: 20)
            Text("\(count)").font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private func grid(days: [Date], scores: [Date: DayScore]) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let leading = (cal.component(.weekday, from: month) - cal.firstWeekday + 7) % 7

        return LazyVGrid(columns: columns, spacing: 10) {
            ForEach(cal.orderedVeryShortWeekdaySymbols.indices, id: \.self) { i in
                Text(cal.orderedVeryShortWeekdaySymbols[i])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<leading, id: \.self) { i in
                Color.clear.frame(height: 1).id("blank-\(i)")
            }
            ForEach(days, id: \.self) { day in
                let isFuture = day > .now
                Button {
                    selected = SelectedDay(date: day)
                } label: {
                    DayCell(date: day,
                            score: scores[day],
                            isToday: cal.isDateInToday(day),
                            isFuture: isFuture)
                }
                .buttonStyle(.plain)
                .disabled(isFuture)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 14) {
            legendItem(theme.trained, theme.activityColor)
            legendItem(theme.sleptWell, theme.sleepColor)
            legendItem(theme.ateWell, theme.nutritionColor)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func legendItem(_ badge: ThemeBadge, _ color: Color) -> some View {
        HStack(spacing: 4) {
            BadgeIcon(badge: badge, color: color, size: 11)
            Text(badge.name).foregroundStyle(.secondary)
        }
        .font(.caption2)
    }

    // MARK: Data

    private func score(for day: Date, mealsByDay: [Date: [Meal]]) -> DayScore {
        Scoring.score(date: day,
                      health: healthByDay[day],
                      meals: mealsByDay[day] ?? [],
                      goals: goals,
                      manualTraining: TrainingDays.contains(manualDates, day))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        let end = cal.date(byAdding: .month, value: 1, to: month) ?? month
        healthByDay = await health.fetchHistory(from: month, to: end)
    }
}

private struct SelectedDay: Identifiable {
    let date: Date
    var id: Date { date }
}

/// One square in the calendar.
struct DayCell: View {
    @Environment(\.theme) private var theme
    let date: Date
    let score: DayScore?
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        VStack(spacing: 3) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.caption2.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? theme.accent : Color.secondary)
            ScoreRing(score: isFuture ? nil : score?.total, size: 34, lineWidth: 3.5)
                .opacity(isFuture ? 0.35 : 1)
            HStack(spacing: 2) {
                BadgeIcon(badge: theme.trained, on: score?.workedOut ?? false, color: theme.activityColor, size: 8)
                BadgeIcon(badge: theme.sleptWell, on: score?.sleptWell ?? false, color: theme.sleepColor, size: 8)
                BadgeIcon(badge: theme.ateWell, on: score?.ateWell ?? false, color: theme.nutritionColor, size: 8)
            }
            .opacity(isFuture ? 0 : 1)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(isToday ? theme.accent.opacity(0.14) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 10))
        .contentShape(Rectangle())
    }
}

// MARK: - Calendar helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }

    /// Start of every day in the month containing `date`.
    func daysInMonth(_ date: Date) -> [Date] {
        let first = startOfMonth(for: date)
        guard let range = range(of: .day, in: .month, for: first) else { return [] }
        return range.compactMap { self.date(byAdding: .day, value: $0 - 1, to: first) }
    }

    /// Weekday initials starting from the locale's first day (Monday in the UK).
    var orderedVeryShortWeekdaySymbols: [String] {
        let symbols = veryShortStandaloneWeekdaySymbols
        let shift = firstWeekday - 1
        return Array(symbols[shift...] + symbols[..<shift])
    }
}
