import SwiftUI

struct SettingsView: View {
    @Environment(HealthStore.self) private var health

    @AppStorage(GoalKey.calories) private var calGoal = GoalDefault.calories
    @AppStorage(GoalKey.protein) private var proteinGoal = GoalDefault.protein
    @AppStorage(GoalKey.carbs) private var carbGoal = GoalDefault.carbs
    @AppStorage(GoalKey.fat) private var fatGoal = GoalDefault.fat
    @AppStorage(GoalKey.sleepHours) private var sleepGoal = GoalDefault.sleepHours
    @AppStorage(GoalKey.trainingCarbBoost) private var carbBoost = GoalDefault.trainingCarbBoost

    @AppStorage(AIModel.key) private var model = AIModel.defaultID
    @AppStorage(UsageTracker.spendKey) private var spend = 0.0
    @AppStorage(UsageTracker.callsKey) private var calls = 0
    @AppStorage("health.saveMeals") private var saveToHealth = true
    @AppStorage(ThemeChoice.key) private var themeChoice = ThemeChoice.automatic.rawValue

    @State private var keyInput = ""
    @State private var hasKey = Keychain.apiKey != nil
    @State private var showReset = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Theme", selection: $themeChoice) {
                        ForEach(ThemeChoice.allCases) { choice in
                            Text(choice.label).tag(choice.rawValue)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Automatic switches to Halloween from 15 to 31 October. The app icon changes with the theme; iOS shows a short pop-up when it does.")
                }
                .themedRows()

                Section {
                    goalRow("Calories", $calGoal, unit: "kcal")
                    goalRow("Protein", $proteinGoal, unit: "g")
                    goalRow("Carbs", $carbGoal, unit: "g")
                    goalRow("Fat", $fatGoal, unit: "g")
                } header: {
                    Text("Daily targets")
                } footer: {
                    Text("Rough starting point for someone lifting: protein about 1.6–2.2g per kg of body weight. Adjust to your own goals.")
                }
                .themedRows()

                Section {
                    goalRow("Extra carbs", $carbBoost, unit: "g")
                } header: {
                    Text("Training days")
                } footer: {
                    Text("Added to your carb target (and \(Int(carbBoost * 4)) kcal to calories) on days with a recorded workout or the \"I trained today\" switch on.")
                }
                .themedRows()

                Section("Sleep") {
                    Stepper(value: $sleepGoal, in: 5...10, step: 0.5) {
                        HStack {
                            Text("Sleep goal")
                            Spacer()
                            Text(String(format: "%.1f h", sleepGoal)).foregroundStyle(.secondary)
                        }
                    }
                }
                .themedRows()

                Section {
                    if hasKey {
                        HStack {
                            Label("API key saved", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                Keychain.apiKey = nil
                                hasKey = false
                            }
                        }
                    } else {
                        SecureField("sk-ant-…", text: $keyInput)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        Button("Save key") {
                            Keychain.apiKey = keyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                            keyInput = ""
                            hasKey = Keychain.apiKey != nil
                        }
                        .disabled(keyInput.isEmpty)
                    }

                    Picker("Model", selection: $model) {
                        ForEach(AIModel.options) { option in
                            Text(option.label).tag(option.id)
                        }
                    }

                    HStack {
                        Text("Estimated spend")
                        Spacer()
                        Text("$\(String(format: "%.3f", spend)) · \(calls) requests")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Button("Reset spend counter") { showReset = true }
                } header: {
                    Text("AI (Claude)")
                } footer: {
                    Text("Get a key at platform.claude.com. The key is stored in your iPhone's Keychain. Spend is an estimate from token counts; your console shows the exact bill.")
                }
                .themedRows()

                Section {
                    Toggle("Save meals to Apple Health", isOn: $saveToHealth)
                    Button("Re-check Health access") {
                        Task { await health.requestAuthorization() }
                    }
                    if let updated = health.lastUpdated {
                        Text("Last synced \(updated.formatted(date: .omitted, time: .shortened))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Apple Health")
                } footer: {
                    Text("To change what the app can read, go to the Health app → your profile → Apps → FuelSleep.")
                }
                .themedRows()
            }
            .themedList()
            .navigationTitle("Settings")
            .confirmationDialog("Reset the spend counter?", isPresented: $showReset) {
                Button("Reset", role: .destructive) { UsageTracker.reset() }
            }
        }
    }

    private func goalRow(_ label: String, _ value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.numberPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
        }
    }
}
