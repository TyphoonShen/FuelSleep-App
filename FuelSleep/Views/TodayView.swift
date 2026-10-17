import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(HealthStore.self) private var health
    @Environment(\.theme) private var theme
    @Query(sort: \Meal.date, order: .reverse) private var allMeals: [Meal]

    @AppStorage(GoalKey.calories) private var calGoal = GoalDefault.calories
    @AppStorage(GoalKey.protein) private var proteinGoal = GoalDefault.protein
    @AppStorage(GoalKey.carbs) private var carbGoal = GoalDefault.carbs
    @AppStorage(GoalKey.fat) private var fatGoal = GoalDefault.fat
    @AppStorage(GoalKey.sleepHours) private var sleepGoal = GoalDefault.sleepHours
    @AppStorage(GoalKey.trainingCarbBoost) private var carbBoost = GoalDefault.trainingCarbBoost
    @AppStorage(GoalKey.manualTrainingDates) private var manualDates = ""

    @State private var advice: CoachAdvice?
    @State private var adviceError: String?
    @State private var loadingAdvice = false
    @State private var lastLogged: Meal?

    private var todaysMeals: [Meal] {
        allMeals.filter { Calendar.current.isDateInToday($0.date) }
    }

    private var isTrainingDay: Bool {
        !health.workouts.isEmpty || TrainingDays.contains(manualDates, .now)
    }

    private var goals: Goals {
        Goals(base: Macros(calories: calGoal, protein: proteinGoal, carbs: carbGoal, fat: fatGoal),
              sleepHours: sleepGoal,
              trainingCarbBoost: carbBoost)
    }

    private var todayScore: DayScore {
        Scoring.score(date: .now,
                      health: health.today,
                      meals: todaysMeals,
                      goals: goals,
                      manualTraining: TrainingDays.contains(manualDates, .now))
    }

    private var context: DayContext {
        DayContext(
            goals: goals,
            eaten: Macros.total(of: todaysMeals),
            mealCount: todaysMeals.count,
            sleepHours: health.sleep?.hours,
            isTrainingDay: isTrainingDay,
            workoutMinutes: health.workouts.reduce(0) { $0 + $1.minutes },
            activeEnergy: health.activeEnergy
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let greeting = theme.greeting {
                        Text(greeting)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if let error = health.lastError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    TodayScoreCard(score: todayScore, health: health.today, meals: todaysMeals, goals: goals)
                    QuickAddCard(lastLogged: $lastLogged)
                    weeklyReviewBanner
                    SleepCard(sleep: health.sleep, goalHours: sleepGoal)
                    ActivityCard(workouts: health.workouts,
                                 activeEnergy: health.activeEnergy,
                                 steps: health.steps,
                                 isTrainingDay: isTrainingDay,
                                 manualTraining: manualBinding)
                    NutritionCard(eaten: context.eaten, targets: context.targets, isTrainingDay: isTrainingDay)
                    InsightsCard(insights: RulesEngine.insights(for: context))
                    coachCard
                }
                .padding()
            }
            .background(theme.background)
            .overlay(alignment: .top) {
                if theme.floatingBats {
                    FloatingBats()
                        .frame(height: 110)
                        .padding(.top, -50)
                }
            }
            .overlay(alignment: .bottom) { UndoToast(meal: $lastLogged) }
            .navigationTitle("Today")
            .refreshable { await health.refresh() }
        }
    }

    /// On Sundays, a nudge to review the week; on Mondays, last week's review.
    @ViewBuilder
    private var weeklyReviewBanner: some View {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: .now)   // 1 = Sunday, 2 = Monday
        if weekday == 1 {
            WeeklyReviewLink(title: "Your week", message: "It's Sunday: see how this week went and get a plan for next week.")
        } else if weekday == 2 {
            WeeklyReviewLink(title: "Last week",
                             message: "Your review of last week is ready.",
                             weekStart: cal.date(byAdding: .day, value: -7, to: cal.startOfWeek(for: .now)))
        }
    }

    private var manualBinding: Binding<Bool> {
        Binding(
            get: { TrainingDays.contains(manualDates, .now) },
            set: { manualDates = TrainingDays.setting(manualDates, .now, trained: $0) }
        )
    }

    // MARK: AI coach

    private var coachCard: some View {
        Card(title: "AI coach", icon: "sparkles") {
            if let advice {
                VStack(alignment: .leading, spacing: 10) {
                    Text(advice.headline).font(.headline)
                    ForEach(Array(advice.tips.enumerated()), id: \.offset) { _, tip in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill").foregroundStyle(.tint)
                            Text(tip)
                        }
                        .font(.subheadline)
                    }
                }
            } else {
                Text("Get personalised advice based on today's meals, training and last night's sleep. About 1p per request on Sonnet, far less on Haiku.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let adviceError {
                Text(adviceError).font(.footnote).foregroundStyle(.red)
            }

            Button {
                Task { await askCoach() }
            } label: {
                HStack {
                    if loadingAdvice { ProgressView() }
                    Text(advice == nil ? "Ask the coach" : "Refresh advice")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(loadingAdvice)
        }
    }

    private func askCoach() async {
        loadingAdvice = true
        adviceError = nil
        defer { loadingAdvice = false }
        do {
            let service = try ClaudeService.fromSettings()
            let summary = RulesEngine.summary(for: context, meals: todaysMeals, workouts: health.workouts)
            advice = try await service.dailyAdvice(summary: summary, tone: theme.coachTone)
        } catch {
            adviceError = error.localizedDescription
        }
    }
}

// MARK: - Cards

struct Card<Content: View>: View {
    @Environment(\.theme) private var theme
    let title: String
    let icon: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.card, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SleepCard: View {
    @Environment(\.theme) private var theme
    let sleep: SleepSummary?
    let goalHours: Double

    var body: some View {
        Card(title: "Last night", icon: "bed.double.fill") {
            if let sleep {
                HStack(alignment: .firstTextBaseline) {
                    Text(format(sleep.asleep)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("asleep").foregroundStyle(.secondary)
                    Spacer()
                    if let start = sleep.start, let end = sleep.end {
                        Text("\(start.formatted(date: .omitted, time: .shortened)) – \(end.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                ProgressView(value: min(sleep.hours / goalHours, 1))
                    .tint(sleep.hours >= goalHours - 0.25 ? theme.great : (sleep.hours >= goalHours - 1 ? theme.fair : theme.poor))
                if sleep.hasStages {
                    HStack {
                        stage("Deep", sleep.deep, theme.deepSleep)
                        stage("Core", sleep.core, theme.coreSleep)
                        stage("REM", sleep.rem, theme.remSleep)
                        stage("Awake", sleep.awake, theme.awake)
                    }
                }
            } else {
                Text("No sleep recorded for last night.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func stage(_ name: String, _ time: TimeInterval, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).foregroundStyle(color)
            Text(format(time)).font(.footnote.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func format(_ t: TimeInterval) -> String {
        let minutes = Int(t / 60)
        return "\(minutes / 60)h \(minutes % 60)m"
    }
}

struct ActivityCard: View {
    let workouts: [WorkoutSummary]
    let activeEnergy: Double
    let steps: Double
    let isTrainingDay: Bool
    @Binding var manualTraining: Bool

    var body: some View {
        Card(title: "Activity", icon: "figure.run") {
            HStack {
                metric("\(Int(activeEnergy))", "active kcal")
                metric(Int(steps).formatted(), "steps")
                metric(isTrainingDay ? "Yes" : "No", "training day")
            }
            if workouts.isEmpty {
                Toggle("I trained today (not recorded on Watch)", isOn: $manualTraining)
                    .font(.subheadline)
            } else {
                ForEach(workouts) { w in
                    HStack {
                        Image(systemName: "dumbbell.fill").foregroundStyle(.tint)
                        Text(w.name)
                        Spacer()
                        Text("\(w.minutes) min · \(w.start.formatted(date: .omitted, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.subheadline)
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title3.weight(.bold)).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NutritionCard: View {
    @Environment(\.theme) private var theme
    let eaten: Macros
    let targets: Macros
    let isTrainingDay: Bool

    var body: some View {
        Card(title: isTrainingDay ? "Nutrition · training-day targets" : "Nutrition", icon: "chart.bar.fill") {
            MacroBar(name: "Calories", value: eaten.calories, target: targets.calories, unit: "kcal", color: theme.calories)
            MacroBar(name: "Protein", value: eaten.protein, target: targets.protein, unit: "g", color: theme.protein)
            MacroBar(name: "Carbs", value: eaten.carbs, target: targets.carbs, unit: "g", color: theme.carbs)
            MacroBar(name: "Fat", value: eaten.fat, target: targets.fat, unit: "g", color: theme.fat)
        }
    }
}

struct MacroBar: View {
    let name: String
    let value: Double
    let target: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name).font(.subheadline.weight(.medium))
                Spacer()
                Text("\(Int(value)) / \(Int(target)) \(unit)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: target > 0 ? min(value / target, 1) : 0)
                .tint(color)
        }
    }
}

struct InsightsCard: View {
    @Environment(\.theme) private var theme
    let insights: [Insight]

    var body: some View {
        Card(title: "Checks", icon: "list.bullet.clipboard") {
            ForEach(insights) { insight in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: insight.icon)
                        .foregroundStyle(theme.insightColor(insight.level))
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(insight.title).font(.subheadline.weight(.semibold))
                        Text(insight.detail).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
