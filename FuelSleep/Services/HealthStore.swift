import Foundation
import HealthKit
import Observation

struct SleepSummary {
    var asleep: TimeInterval = 0
    var inBed: TimeInterval = 0
    var awake: TimeInterval = 0
    var core: TimeInterval = 0
    var deep: TimeInterval = 0
    var rem: TimeInterval = 0
    var start: Date?
    var end: Date?

    var hours: Double { asleep / 3600 }
    var hasStages: Bool { core + deep + rem > 0 }
}

/// Everything Apple Health knows about one day.
struct DayHealth {
    var sleep: SleepSummary?
    var workouts: [WorkoutSummary] = []
    var steps: Double = 0
    var activeEnergy: Double = 0
}

struct WorkoutSummary: Identifiable {
    let id: UUID
    let name: String
    let start: Date
    let duration: TimeInterval
    let energy: Double?   // kcal

    var minutes: Int { Int(duration / 60) }
}

/// Reads sleep, workouts and activity from Apple Health, and writes logged meals back to it.
@Observable
@MainActor
final class HealthStore {
    private let store = HKHealthStore()

    var sleep: SleepSummary?
    var workouts: [WorkoutSummary] = []
    var activeEnergy: Double = 0
    var steps: Double = 0
    var lastError: String?
    var isLoading = false
    var lastUpdated: Date?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    private var readTypes: Set<HKObjectType> {
        [
            HKCategoryType(.sleepAnalysis),
            HKObjectType.workoutType(),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.stepCount)
        ]
    }

    private var nutritionTypes: [(HKQuantityTypeIdentifier, HKUnit)] {
        [
            (.dietaryEnergyConsumed, .kilocalorie()),
            (.dietaryProtein, .gram()),
            (.dietaryCarbohydrates, .gram()),
            (.dietaryFatTotal, .gram())
        ]
    }

    private var writeTypes: Set<HKSampleType> {
        Set(nutritionTypes.map { HKQuantityType($0.0) })
    }

    static let mealIDKey = "FuelSleepMealID"

    // MARK: - Permissions

    func requestAuthorization() async {
        guard isAvailable else {
            lastError = "Apple Health isn't available on this device."
            return
        }
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Reading

    func refresh() async {
        guard isAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        lastError = nil

        do {
            sleep = try await fetchLastNightSleep()
            workouts = try await fetchTodayWorkouts()
            activeEnergy = try await fetchTodaySum(.activeEnergyBurned, unit: .kilocalorie())
            steps = try await fetchTodaySum(.stepCount, unit: .count())
            lastUpdated = .now
        } catch {
            // Note: if you denied read access, HealthKit just returns no data rather than an error.
            lastError = error.localizedDescription
        }
    }

    /// Sleep between 6pm yesterday and 2pm today.
    private func fetchLastNightSleep() async throws -> SleepSummary? {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        guard let windowStart = cal.date(byAdding: .hour, value: -6, to: today),
              let windowEnd = cal.date(byAdding: .hour, value: 14, to: today) else { return nil }
        let samples = try await fetchSleepSamples(from: windowStart, to: windowEnd)
        return Self.summarizeSleep(samples)
    }

    private func fetchSleepSamples(from start: Date, to end: Date) async throws -> [HKCategorySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.categorySample(type: HKCategoryType(.sleepAnalysis), predicate: predicate)],
            sortDescriptors: [SortDescriptor(\.startDate)]
        )
        return try await descriptor.result(for: store)
    }

    /// Turns one night's raw sleep samples into totals.
    private static func summarizeSleep(_ samples: [HKCategorySample]) -> SleepSummary? {
        guard !samples.isEmpty else { return nil }

        // Watch and iPhone can both record sleep; counting both would double it.
        // Use whichever single source recorded the most time asleep.
        let bySource = Dictionary(grouping: samples) { $0.sourceRevision.source.bundleIdentifier }
        func asleepTime(_ list: [HKCategorySample]) -> TimeInterval {
            list.filter { isAsleep($0.value) }
                .reduce(0) { $0 + $1.endDate.timeIntervalSince($1.startDate) }
        }
        guard let best = bySource.values.max(by: { asleepTime($0) < asleepTime($1) }) else { return nil }

        var summary = SleepSummary()
        for sample in best {
            let length = sample.endDate.timeIntervalSince(sample.startDate)
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            switch value {
            case .inBed:
                summary.inBed += length
            case .awake:
                summary.awake += length
            case .asleepCore:
                summary.core += length
                summary.asleep += length
            case .asleepDeep:
                summary.deep += length
                summary.asleep += length
            case .asleepREM:
                summary.rem += length
                summary.asleep += length
            case .asleepUnspecified:
                summary.asleep += length
            @unknown default:
                break
            }
            if isAsleep(sample.value) {
                if summary.start == nil || sample.startDate < summary.start! { summary.start = sample.startDate }
                if summary.end == nil || sample.endDate > summary.end! { summary.end = sample.endDate }
            }
        }
        return summary.asleep > 0 ? summary : nil
    }

    private static func isAsleep(_ raw: Int) -> Bool {
        guard let value = HKCategoryValueSleepAnalysis(rawValue: raw) else { return false }
        switch value {
        case .asleepUnspecified, .asleepCore, .asleepDeep, .asleepREM: return true
        default: return false
        }
    }

    private func fetchTodayWorkouts() async throws -> [WorkoutSummary] {
        try await fetchWorkouts(from: Calendar.current.startOfDay(for: .now), to: nil)
    }

    private func fetchWorkouts(from start: Date, to end: Date?) async throws -> [WorkoutSummary] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKSampleQueryDescriptor(
            predicates: [.workout(predicate)],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)]
        )
        let results = try await descriptor.result(for: store)
        return results.map { w in
            WorkoutSummary(
                id: w.uuid,
                name: w.workoutActivityType.displayName,
                start: w.startDate,
                duration: w.duration,
                energy: w.statistics(for: HKQuantityType(.activeEnergyBurned))?
                    .sumQuantity()?.doubleValue(for: .kilocalorie())
            )
        }
    }

    private func fetchTodaySum(_ id: HKQuantityTypeIdentifier, unit: HKUnit) async throws -> Double {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        let descriptor = HKStatisticsQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum
        )
        let stats = try await descriptor.result(for: store)
        return stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
    }

    // MARK: - History

    /// Today's data in the same shape as a history day.
    var today: DayHealth {
        DayHealth(sleep: sleep, workouts: workouts, steps: steps, activeEnergy: activeEnergy)
    }

    /// Sleep, workouts, steps and active energy for every day from `start` up to (not including) `end`.
    /// Keys are the start of each day.
    func fetchHistory(from start: Date, to end: Date) async -> [Date: DayHealth] {
        guard isAvailable else { return [:] }
        let cal = Calendar.current
        var days: [Date: DayHealth] = [:]

        // Sleep counts towards the day you wake up on: anything starting from 6pm the
        // evening before until 6pm on the day itself.
        let shift: TimeInterval = 6 * 3600
        if let samples = try? await fetchSleepSamples(from: start.addingTimeInterval(-shift),
                                                      to: end.addingTimeInterval(-shift)) {
            let byNight = Dictionary(grouping: samples) { cal.startOfDay(for: $0.startDate.addingTimeInterval(shift)) }
            for (day, nightSamples) in byNight {
                days[day, default: DayHealth()].sleep = Self.summarizeSleep(nightSamples)
            }
        }

        if let list = try? await fetchWorkouts(from: start, to: end) {
            for w in list {
                days[cal.startOfDay(for: w.start), default: DayHealth()].workouts.append(w)
            }
        }

        if let steps = try? await dailySums(.stepCount, unit: .count(), from: start, to: end) {
            for (day, value) in steps { days[day, default: DayHealth()].steps = value }
        }

        if let energy = try? await dailySums(.activeEnergyBurned, unit: .kilocalorie(), from: start, to: end) {
            for (day, value) in energy { days[day, default: DayHealth()].activeEnergy = value }
        }

        return days
    }

    private func dailySums(_ id: HKQuantityTypeIdentifier, unit: HKUnit,
                           from start: Date, to end: Date) async throws -> [Date: Double] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: .quantitySample(type: HKQuantityType(id), predicate: predicate),
            options: .cumulativeSum,
            anchorDate: Calendar.current.startOfDay(for: start),
            intervalComponents: DateComponents(day: 1)
        )
        let collection = try await descriptor.result(for: store)
        var out: [Date: Double] = [:]
        for stats in collection.statistics() {
            if let value = stats.sumQuantity()?.doubleValue(for: unit) {
                out[Calendar.current.startOfDay(for: stats.startDate)] = value
            }
        }
        return out
    }

    // MARK: - Writing meals

    func saveMeal(id: UUID, name: String, date: Date, macros: Macros) async {
        guard isAvailable else { return }
        let metadata: [String: Any] = [
            HKMetadataKeyFoodType: name,
            Self.mealIDKey: id.uuidString
        ]
        let values = [macros.calories, macros.protein, macros.carbs, macros.fat]
        var samples: [HKObject] = []
        for (index, (typeID, unit)) in nutritionTypes.enumerated() where values[index] > 0 {
            samples.append(HKQuantitySample(
                type: HKQuantityType(typeID),
                quantity: HKQuantity(unit: unit, doubleValue: values[index]),
                start: date,
                end: date,
                metadata: metadata
            ))
        }
        guard !samples.isEmpty else { return }
        do {
            try await store.save(samples)
        } catch {
            lastError = "Couldn't save meal to Health: \(error.localizedDescription)"
        }
    }

    func deleteMeal(id: UUID) {
        guard isAvailable else { return }
        let predicate = HKQuery.predicateForObjects(withMetadataKey: Self.mealIDKey,
                                                    allowedValues: [id.uuidString])
        for (typeID, _) in nutritionTypes {
            store.deleteObjects(of: HKQuantityType(typeID), predicate: predicate) { _, _, _ in }
        }
    }
}

extension HKWorkoutActivityType {
    var displayName: String {
        switch self {
        case .traditionalStrengthTraining: return "Strength training"
        case .functionalStrengthTraining: return "Functional strength"
        case .highIntensityIntervalTraining: return "HIIT"
        case .coreTraining: return "Core"
        case .crossTraining: return "Cross training"
        case .mixedCardio: return "Cardio"
        case .running: return "Run"
        case .walking: return "Walk"
        case .cycling: return "Cycle"
        case .swimming: return "Swim"
        case .rowing: return "Row"
        case .elliptical: return "Elliptical"
        case .stairClimbing: return "Stairs"
        case .yoga: return "Yoga"
        case .pilates: return "Pilates"
        case .soccer: return "Football"
        case .basketball: return "Basketball"
        case .tennis: return "Tennis"
        case .boxing: return "Boxing"
        case .hiking: return "Hike"
        default: return "Workout"
        }
    }
}
