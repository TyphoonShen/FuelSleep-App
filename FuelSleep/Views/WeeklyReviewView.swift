import SwiftUI
import SwiftData
import Charts

/// One week at a glance: average score, badges, charts, how often you hit your targets,
/// and an AI-written review. Tap a bar in any chart to see that day's numbers.
struct WeeklyReviewView: View {
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

    @State private var weekStart: Date
    @State private var healthByDay: [Date: DayHealth] = [:]
    @State private var loading = false

    @State private var review: WeeklyReview?
    @State private var reviewError: String?
    @State private var writing = false

    @State private var selectedScoreDay: Date?
    @State private var selectedSleepDay: Date?
    @State private var selectedCarbDay: Date?

    private let cal = Calendar.current

    init(weekStart: Date? = nil) {
        _weekStart = State(initialValue: Calendar.current.startOfWeek(for: weekStart ?? .now))
    }

    private var goals: Goals {
        Goals(base: Macros(calories: calGoal, protein: proteinGoal, carbs: carbGoal, fat: fatGoal),
              sleepHours: sleepGoal,
              trainingCarbBoost: carbBoost)
    }

    private var previousStart: Date { cal.date(byAdding: .day, value: -7, to: weekStart) ?? weekStart }
    private var nextStart: Date { cal.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart }
    private var isCurrentWeek: Bool { cal.isDate(weekStart, equalTo: .now, toGranularity: .weekOfYear) }

    var body: some View {
        let stats = WeekStats.build(start: weekStart, healthByDay: healthByDay, meals: meals,
                                    goals: goals, manualDates: manualDates)
        let previous = WeekStats.build(start: previousStart, healthByDay: healthByDay, meals: meals,
                                       goals: goals, manualDates: manualDates)

        ScrollView {
            VStack(spacing: 16) {
                header
                overview(stats, previous: previous)
                if stats.days.isEmpty {
                    Text("This week hasn't started yet.")
                        .foregroundStyle(.secondary)
                } else {
                    scoreChart(stats)
                    sleepChart(stats)
                    carbChart(stats)
                    hitRates(stats)
                    aiReview(stats, previous: previous)
                }
            }
            .padding()
        }
        .background(theme.background)
        .navigationTitle("Weekly review")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: weekStart) {
            review = WeeklyReviewStore.load(for: weekStart)
            reviewError = nil
            await load()
        }
    }

    // MARK: Header

    private var header: some View {
        let lastDay = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return HStack {
            Button { weekStart = previousStart } label: {
                Image(systemName: "chevron.left").font(.title3.weight(.semibold))
            }
            Spacer()
            VStack(spacing: 2) {
                Text("\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(lastDay.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.title3.weight(.semibold))
                HStack(spacing: 6) {
                    Text(weekLabel).font(.caption).foregroundStyle(.secondary)
                    if loading { ProgressView().controlSize(.mini) }
                }
            }
            Spacer()
            Button { weekStart = nextStart } label: {
                Image(systemName: "chevron.right").font(.title3.weight(.semibold))
            }
            .disabled(isCurrentWeek)
        }
        .padding(.horizontal, 4)
    }

    private var weekLabel: String {
        if isCurrentWeek { return "This week (so far)" }
        if cal.isDate(nextStart, equalTo: .now, toGranularity: .weekOfYear) { return "Last week" }
        return weekStart.formatted(.dateTime.year())
    }

    // MARK: Overview

    private func overview(_ stats: WeekStats, previous: WeekStats) -> some View {
        Card(title: "Overview", icon: "star.circle.fill") {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 4) {
                    ScoreRing(score: stats.averageScore, size: 76)
                        .padding(.top, theme.pumpkinRing ? 8 : 0)
                    Text("Average").font(.caption).foregroundStyle(.secondary)
                    if let now = stats.averageScore, let before = previous.averageScore {
                        let delta = now - before
                        HStack(spacing: 2) {
                            Image(systemName: delta > 0 ? "arrow.up" : (delta < 0 ? "arrow.down" : "equal"))
                                .foregroundStyle(delta > 0 ? theme.great : (delta < 0 ? theme.poor : Color.secondary))
                            Text(delta == 0 ? "same as last week" : "\(abs(delta)) vs last week")
                                .foregroundStyle(.secondary)
                        }
                        .font(.caption2.weight(.semibold))
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    statLine(theme.trained, theme.activityColor, "\(stats.trainedDays)", "days trained")
                    statLine(theme.sleptWell, theme.sleepColor, "\(stats.sleptWellNights)", "nights slept well")
                    statLine(theme.ateWell, theme.nutritionColor, "\(stats.ateWellDays)", "days ate well")
                    HStack(spacing: 8) {
                        Image(systemName: "bed.double.fill").foregroundStyle(theme.sleepColor).frame(width: 20)
                        Text(stats.averageSleep.map { ScoreText.duration($0 * 3600) } ?? "–")
                            .font(.subheadline.weight(.bold)).monospacedDigit()
                        Text("avg sleep").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func statLine(_ badge: ThemeBadge, _ color: Color, _ value: String, _ label: String) -> some View {
        HStack(spacing: 8) {
            BadgeIcon(badge: badge, color: color, size: 15).frame(width: 20)
            Text(value).font(.subheadline.weight(.bold)).monospacedDigit()
            Text(label).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    // MARK: Charts

    private var weekDomain: ClosedRange<Date> { weekStart...nextStart }

    private func dayAxis() -> some AxisContent {
        AxisMarks(values: .stride(by: .day)) { _ in
            AxisValueLabel(format: .dateTime.weekday(.abbreviated), centered: true)
        }
    }

    private func stat(on date: Date?, in stats: WeekStats) -> DayStat? {
        guard let date else { return nil }
        return stats.days.first { cal.isDate($0.date, inSameDayAs: date) }
    }

    private func tooltip(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption.weight(.semibold))
            ForEach(lines, id: \.self) { Text($0).font(.caption2).foregroundStyle(.secondary) }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    private func num(_ value: Int?) -> String {
        value.map { String($0) } ?? "–"
    }

    private func scoreLines(_ s: DayStat) -> [String] {
        let label = theme.scoreLabel(s.score.total) + (s.isComplete ? "" : " so far")
        return [
            "Score " + num(s.score.total) + " · " + label,
            "Sleep " + num(s.score.sleep) + " · Food " + num(s.score.nutrition) + " · Activity " + num(s.score.activity)
        ]
    }

    private func sleepLines(_ sleep: SleepSummary) -> [String] {
        let stages = sleep.hasStages
            ? "Deep " + ScoreText.duration(sleep.deep) + " · REM " + ScoreText.duration(sleep.rem)
            : "No stage data"
        return [ScoreText.duration(sleep.asleep) + " asleep", stages]
    }

    private func carbTitle(_ s: DayStat) -> String {
        s.date.formatted(.dateTime.weekday(.wide)) + (s.isTraining ? " · training day" : " · rest day")
    }

    private func carbLines(_ s: DayStat) -> [String] {
        [
            "Carbs \(Int(s.eaten.carbs)) / \(Int(s.targets.carbs)) g (\(s.carbPercent ?? 0)%)",
            "Protein \(Int(s.eaten.protein)) / \(Int(s.targets.protein)) g"
        ]
    }

    private func scoreChart(_ stats: WeekStats) -> some View {
        let selected = stat(on: selectedScoreDay, in: stats)
        return Card(title: "Daily score", icon: "chart.bar.fill") {
            Chart {
                ForEach(stats.days) { d in
                    if let total = d.score.total {
                        BarMark(x: .value("Day", d.date, unit: .day),
                                y: .value("Score", total),
                                width: .ratio(0.6))
                            .foregroundStyle(theme.scoreColor(total).opacity(d.isComplete ? 1 : 0.45))
                            .cornerRadius(4)
                    }
                }
                if let avg = stats.averageScore {
                    RuleMark(y: .value("Average", avg))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("avg \(avg)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                if let s = selected {
                    RuleMark(x: .value("Day", s.date, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.25))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            tooltip(s.date.formatted(.dateTime.weekday(.wide)), scoreLines(s))
                        }
                }
            }
            .chartXScale(domain: weekDomain)
            .chartYScale(domain: 0...100)
            .chartXAxis { dayAxis() }
            .chartYAxis { AxisMarks(values: [0, 50, 100]) }
            .chartXSelection(value: $selectedScoreDay)
            .frame(height: 180)
        }
    }

    private func sleepChart(_ stats: WeekStats) -> some View {
        let selected = stat(on: selectedSleepDay, in: stats)
        let maxHours = max(stats.days.compactMap(\.sleepHours).max() ?? 0, goals.sleepHours)
        return Card(title: "Sleep", icon: "bed.double.fill") {
            if stats.days.allSatisfy({ $0.sleepHours == nil }) {
                Text("No sleep recorded this week.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(stats.days) { d in
                        if let h = d.sleepHours {
                            BarMark(x: .value("Night", d.date, unit: .day),
                                    y: .value("Hours", h),
                                    width: .ratio(0.6))
                                .foregroundStyle(theme.sleepColor)
                                .cornerRadius(4)
                        }
                    }
                    RuleMark(y: .value("Goal", goals.sleepHours))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("goal \(ScoreText.duration(goals.sleepHours * 3600))")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    if let s = selected, let sleep = s.health?.sleep {
                        RuleMark(x: .value("Night", s.date, unit: .day))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                tooltip("Night before \(s.date.formatted(.dateTime.weekday(.wide)))", sleepLines(sleep))
                            }
                    }
                }
                .chartXScale(domain: weekDomain)
                .chartYScale(domain: 0...(maxHours + 1).rounded(.up))
                .chartXAxis { dayAxis() }
                .chartYAxis {
                    AxisMarks(values: .stride(by: 2)) { value in
                        AxisGridLine()
                        AxisValueLabel { if let h = value.as(Double.self) { Text("\(Int(h))h") } }
                    }
                }
                .chartXSelection(value: $selectedSleepDay)
                .frame(height: 170)
                Text("Sleep is shown on the day you woke up.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func carbChart(_ stats: WeekStats) -> some View {
        let selected = stat(on: selectedCarbDay, in: stats)
        let withMeals = stats.days.filter { $0.carbPercent != nil }
        let topPercent = max(withMeals.compactMap(\.carbPercent).max() ?? 100, 110)
        let trainingAvg = stats.averageCarbPercent(training: true)
        let restAvg = stats.averageCarbPercent(training: false)

        return Card(title: "Carbs vs target", icon: "bolt.fill") {
            if withMeals.isEmpty {
                Text("No meals logged this week.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart {
                    ForEach(withMeals) { d in
                        BarMark(x: .value("Day", d.date, unit: .day),
                                y: .value("% of carb target", d.carbPercent ?? 0),
                                width: .ratio(0.6))
                            .foregroundStyle(by: .value("Day type", d.isTraining ? "Training day" : "Rest day"))
                            .opacity(d.isComplete ? 1 : 0.45)
                            .cornerRadius(4)
                    }
                    RuleMark(y: .value("Target", 100))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(Color.secondary)
                        .annotation(position: .top, alignment: .leading) {
                            Text("target").font(.caption2).foregroundStyle(.secondary)
                        }
                    if let s = selected, s.hasMeals {
                        RuleMark(x: .value("Day", s.date, unit: .day))
                            .foregroundStyle(Color.secondary.opacity(0.25))
                            .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                                tooltip(carbTitle(s), carbLines(s))
                            }
                    }
                }
                .chartForegroundStyleScale(["Training day": theme.chartTraining, "Rest day": theme.chartRest])
                .chartLegend(position: .top, alignment: .leading)
                .chartXScale(domain: weekDomain)
                .chartYScale(domain: 0...topPercent)
                .chartXAxis { dayAxis() }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { value in
                        AxisGridLine()
                        AxisValueLabel { if let p = value.as(Int.self) { Text("\(p)%") } }
                    }
                }
                .chartXSelection(value: $selectedCarbDay)
                .frame(height: 190)

                HStack(spacing: 16) {
                    averageLabel("Training days", trainingAvg)
                    averageLabel("Rest days", restAvg)
                }
            }
        }
    }

    private func averageLabel(_ title: String, _ percent: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(percent.map { "\($0)%" } ?? "–").font(.subheadline.weight(.bold)).monospacedDigit()
            Text("\(title), avg").font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: Hit rates

    private func hitRates(_ stats: WeekStats) -> some View {
        let hits = stats.macroHits
        let colors: [String: Color] = ["Calories": theme.calories, "Protein": theme.protein,
                                       "Carbs": theme.carbs, "Fat": theme.fat]
        return Card(title: "Targets hit", icon: "target") {
            if (hits.first?.of ?? 0) == 0 {
                Text("Log meals on a few days to see how often you hit each target.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(hits) { h in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(h.name).font(.subheadline.weight(.medium))
                            Spacer()
                            Text("\(h.hit) of \(h.of) days")
                                .font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                        }
                        ProgressView(value: h.rate).tint(colors[h.name] ?? theme.accent)
                    }
                }
                Text("Finished days with meals logged. Protein counts when you reach 95% of target; calories and carbs within 10%; fat within 20%.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: AI review

    private func aiReview(_ stats: WeekStats, previous: WeekStats) -> some View {
        Card(title: "Coach's review", icon: "sparkles") {
            if let review {
                VStack(alignment: .leading, spacing: 12) {
                    Text(review.headline).font(.headline)
                    reviewSection("Went well", icon: "checkmark.circle.fill", color: theme.great, items: review.wentWell)
                    reviewSection("Focus next week", icon: "scope", color: theme.warn, items: [review.focus])
                    reviewSection("Plan", icon: "list.number", color: theme.accent, items: review.plan, numbered: true)
                    if let at = review.generatedAt {
                        Text("Written \(at.formatted(.relative(presentation: .named)))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            } else {
                Text(isCurrentWeek
                     ? "Get a short review of your week so far: what went well, one thing to fix, and a plan. About 1p; saved for this week."
                     : "Get a short review of this week: what went well, one thing to fix, and a plan. About 1p; saved for this week.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let reviewError {
                Text(reviewError).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await writeReview(stats, previous: previous) }
            } label: {
                HStack {
                    if writing { ProgressView() }
                    Text(review == nil ? "Write my weekly review" : "Rewrite review")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(writing || loading || stats.averageScore == nil)
        }
    }

    private func reviewSection(_ title: String, icon: String, color: Color, items: [String], numbered: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .top, spacing: 6) {
                    Text(numbered ? "\(index + 1)." : "•").foregroundStyle(.secondary)
                    Text(item)
                }
                .font(.subheadline)
            }
        }
    }

    // MARK: Data

    private func load() async {
        loading = true
        defer { loading = false }
        healthByDay = await health.fetchHistory(from: previousStart, to: nextStart)
    }

    private func writeReview(_ stats: WeekStats, previous: WeekStats) async {
        writing = true
        reviewError = nil
        defer { writing = false }
        do {
            let summary = stats.summary(previousAverage: previous.averageScore, goals: goals)
            let result = try await ClaudeService.fromSettings().weeklyReview(summary: summary, tone: theme.coachTone)
            review = result
            WeeklyReviewStore.save(result, for: weekStart)
        } catch {
            reviewError = error.localizedDescription
        }
    }
}

/// The card on the History tab (and the Sunday/Monday banner on Today) that opens the review.
struct WeeklyReviewLink: View {
    @Environment(\.theme) private var theme
    var title = "Weekly review"
    var message = "Charts, targets hit and a coach's review of your week."
    var weekStart: Date? = nil

    var body: some View {
        NavigationLink {
            WeeklyReviewView(weekStart: weekStart)
        } label: {
            Card(title: title, icon: "chart.bar.doc.horizontal") {
                HStack {
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
