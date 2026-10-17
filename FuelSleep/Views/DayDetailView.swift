import SwiftUI

// MARK: - Shared score pieces

/// Circular progress ring with the score in the middle.
/// In the Halloween theme it grows a pumpkin stem.
struct ScoreRing: View {
    @Environment(\.theme) private var theme
    let score: Int?
    var size: CGFloat = 72
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(theme.ringTrack, lineWidth: lineWidth)
            if let score {
                Circle()
                    .trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(theme.scoreColor(score), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .monospacedDigit()
            } else {
                Text("–")
                    .font(.system(size: size * 0.3, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .top) {
            if theme.pumpkinRing && size >= 60 {
                PumpkinStem(size: size)
            }
        }
    }
}

/// The little green stem and leaf on top of the pumpkin score ring.
private struct PumpkinStem: View {
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Capsule()
                .fill(Color(hex: 0x5C8A2E))
                .frame(width: size * 0.08, height: size * 0.2)
                .rotationEffect(.degrees(14), anchor: .bottom)
            Ellipse()
                .fill(Color(hex: 0x7DBF3A))
                .frame(width: size * 0.13, height: size * 0.065)
                .rotationEffect(.degrees(-25))
                .offset(x: size * 0.05, y: -size * 0.07)
        }
        .offset(y: -size * 0.15)
        .accessibilityHidden(true)
    }
}

/// One line of the score breakdown: icon, name, detail, and score.
struct PillarRow: View {
    @Environment(\.theme) private var theme
    let badge: ThemeBadge
    let name: String
    let detail: String
    let score: Int?
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            BadgeIcon(badge: badge, color: tint, size: 16)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(score.map { "\($0)" } ?? "–")
                .font(.headline.monospacedDigit())
                .foregroundStyle(theme.scoreColor(score))
        }
    }
}

/// Builds the detail text under each part of the score.
enum ScoreText {
    static func sleep(_ s: SleepSummary?, goal: Double) -> String {
        guard let s else { return "No sleep recorded" }
        return "\(duration(s.asleep)) asleep · goal \(String(format: "%g", goal))h"
    }

    static func nutrition(_ meals: [Meal], targets: Macros) -> String {
        guard !meals.isEmpty else { return "No meals logged" }
        let e = Macros.total(of: meals)
        return "\(Int(e.calories)) / \(Int(targets.calories)) kcal · P \(Int(e.protein))g · C \(Int(e.carbs))g"
    }

    static func activity(_ h: DayHealth?, workedOut: Bool) -> String {
        if let w = h?.workouts, !w.isEmpty {
            let mins = w.reduce(0) { $0 + $1.minutes }
            let names = Array(Set(w.map(\.name))).sorted().joined(separator: ", ")
            return "\(names) · \(mins) min"
        }
        if workedOut { return "Trained (marked by hand)" }
        let steps = Int(h?.steps ?? 0)
        return steps > 0 ? "Rest day · \(steps.formatted()) steps" : "No activity data"
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return "\(m / 60)h \(m % 60)m"
    }
}

/// The score card at the top of the Today tab.
struct TodayScoreCard: View {
    @Environment(\.theme) private var theme
    let score: DayScore
    let health: DayHealth
    let meals: [Meal]
    let goals: Goals

    var body: some View {
        Card(title: "Today's score so far", icon: "star.circle.fill") {
            HStack(alignment: .center, spacing: 16) {
                VStack(spacing: 4) {
                    ScoreRing(score: score.total, size: 76)
                        .padding(.top, theme.pumpkinRing ? 8 : 0)
                    Text(theme.scoreLabel(score.total))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(theme.scoreColor(score.total))
                }
                VStack(spacing: 10) {
                    PillarRow(badge: theme.sleptWell, name: "Sleep",
                              detail: ScoreText.sleep(health.sleep, goal: goals.sleepHours),
                              score: score.sleep, tint: theme.sleepColor)
                    PillarRow(badge: theme.ateWell, name: "Nutrition",
                              detail: ScoreText.nutrition(meals, targets: goals.targets(isTrainingDay: score.workedOut)),
                              score: score.nutrition, tint: theme.nutritionColor)
                    PillarRow(badge: theme.trained, name: "Activity",
                              detail: ScoreText.activity(health, workedOut: score.workedOut),
                              score: score.activity, tint: theme.activityColor)
                }
            }
        }
    }
}

// MARK: - Day detail

struct DayDetailView: View {
    let date: Date
    let health: DayHealth?
    let meals: [Meal]
    let goals: Goals

    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @AppStorage(GoalKey.manualTrainingDates) private var manualDates = ""
    @State private var editing: Meal?

    private var score: DayScore {
        Scoring.score(date: date, health: health, meals: meals, goals: goals,
                      manualTraining: TrainingDays.contains(manualDates, date))
    }

    private var trainedBinding: Binding<Bool> {
        Binding(
            get: { TrainingDays.contains(manualDates, date) },
            set: { manualDates = TrainingDays.setting(manualDates, date, trained: $0) }
        )
    }

    var body: some View {
        let score = self.score
        let targets = goals.targets(isTrainingDay: score.workedOut)

        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    // Headline score
                    VStack(spacing: 6) {
                        ScoreRing(score: score.total, size: 120, lineWidth: 12)
                            .padding(.top, theme.pumpkinRing ? 14 : 0)
                        Text(score.isPartial ? "\(theme.scoreLabel(score.total)) so far" : theme.scoreLabel(score.total))
                            .font(.headline)
                            .foregroundStyle(theme.scoreColor(score.total))
                        HStack(spacing: 14) {
                            badge(theme.trained, score.workedOut, theme.activityColor)
                            badge(theme.sleptWell, score.sleptWell, theme.sleepColor)
                            badge(theme.ateWell, score.ateWell, theme.nutritionColor)
                        }
                        .padding(.top, 4)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)

                    Card(title: "Breakdown", icon: "chart.pie.fill") {
                        PillarRow(badge: theme.sleptWell, name: "Sleep · 35%",
                                  detail: ScoreText.sleep(health?.sleep, goal: goals.sleepHours),
                                  score: score.sleep, tint: theme.sleepColor)
                        PillarRow(badge: theme.ateWell, name: "Nutrition · 40%",
                                  detail: ScoreText.nutrition(meals, targets: targets),
                                  score: score.nutrition, tint: theme.nutritionColor)
                        PillarRow(badge: theme.trained, name: "Activity · 25%",
                                  detail: ScoreText.activity(health, workedOut: score.workedOut),
                                  score: score.activity, tint: theme.activityColor)
                        if health?.workouts.isEmpty ?? true {
                            Toggle("I trained this day (not on Watch)", isOn: trainedBinding)
                                .font(.subheadline)
                        }
                    }

                    if !meals.isEmpty {
                        NutritionCard(eaten: Macros.total(of: meals), targets: targets, isTrainingDay: score.workedOut)
                    }

                    SleepCard(sleep: health?.sleep, goalHours: goals.sleepHours)

                    if let workouts = health?.workouts, !workouts.isEmpty {
                        Card(title: "Workouts", icon: "figure.strengthtraining.traditional") {
                            ForEach(workouts) { w in
                                HStack {
                                    Text(w.name)
                                    Spacer()
                                    Text("\(w.minutes) min · \(w.start.formatted(date: .omitted, time: .shortened))")
                                        .foregroundStyle(.secondary)
                                }
                                .font(.subheadline)
                            }
                        }
                    }

                    Card(title: "Meals", icon: "fork.knife") {
                        if meals.isEmpty {
                            Text("No meals logged this day.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(meals.sorted(by: { $0.date < $1.date })) { meal in
                                Button { editing = meal } label: { MealRow(meal: meal) }
                                    .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .background(theme.background)
            .navigationTitle(date.formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { meal in
                AddMealView(existing: meal)
            }
        }
    }

    private func badge(_ badge: ThemeBadge, _ on: Bool, _ color: Color) -> some View {
        VStack(spacing: 3) {
            BadgeIcon(badge: badge, on: on, color: color, size: 17)
            Text(badge.name)
                .font(.caption2)
                .foregroundStyle(on ? Color.primary : Color.secondary)
        }
    }
}
