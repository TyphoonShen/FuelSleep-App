import SwiftUI
import SwiftData

/// Add a new meal (from a photo, a description, a favourite or by hand), or edit an existing one.
struct AddMealView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(HealthStore.self) private var health
    @AppStorage("health.saveMeals") private var saveToHealth = true

    private let existing: Meal?
    private let image: UIImage?
    private let originalName: String?

    @State private var name = ""
    @State private var calories: Double = 0
    @State private var protein: Double = 0
    @State private var carbs: Double = 0
    @State private var fat: Double = 0
    @State private var date = Date.now
    @State private var notes = ""
    @State private var hint = ""
    @State private var mealText = ""
    @State private var isFavorite = false

    @State private var analyzing = false
    @State private var analysisError: String?
    @State private var confidence: String?

    @FocusState private var describeFocused: Bool

    /// New meal from a photo, or blank (describe it or type it in).
    init(image: UIImage? = nil) {
        self.image = image
        self.existing = nil
        self.originalName = nil
    }

    /// New meal pre-filled from a favourite or a past meal, so you can adjust it before logging.
    init(draft: MealDraft) {
        self.image = draft.photo.flatMap { UIImage(data: $0) }
        self.existing = nil
        self.originalName = draft.name
        _name = State(initialValue: draft.name)
        _calories = State(initialValue: draft.macros.calories)
        _protein = State(initialValue: draft.macros.protein)
        _carbs = State(initialValue: draft.macros.carbs)
        _fat = State(initialValue: draft.macros.fat)
    }

    /// Edit a meal you've already logged.
    init(existing: Meal) {
        self.existing = existing
        self.image = existing.photo.flatMap { UIImage(data: $0) }
        self.originalName = existing.name
        _name = State(initialValue: existing.name)
        _calories = State(initialValue: existing.calories)
        _protein = State(initialValue: existing.protein)
        _carbs = State(initialValue: existing.carbs)
        _fat = State(initialValue: existing.fat)
        _date = State(initialValue: existing.date)
        _notes = State(initialValue: existing.notes)
    }

    /// A brand-new blank meal: show the "describe it" box first.
    private var isBlankNewMeal: Bool {
        existing == nil && image == nil && originalName == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                if let image {
                    Section {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowInsets(EdgeInsets())

                        if existing == nil && originalName == nil {
                            TextField("Optional details, e.g. \"200g chicken, cooked in butter\"", text: $hint, axis: .vertical)
                            Button {
                                Task { await analyze(image) }
                            } label: {
                                HStack {
                                    if analyzing { ProgressView() } else { Image(systemName: "sparkles") }
                                    Text(analyzing ? "Analysing…" : (confidence == nil ? "Analyse with AI" : "Analyse again"))
                                }
                            }
                            .disabled(analyzing)
                        }
                    } footer: {
                        analysisFooter
                    }
                    .themedRows()
                }

                if isBlankNewMeal {
                    Section {
                        TextField("e.g. 2 eggs, 2 toast with butter, flat white", text: $mealText, axis: .vertical)
                            .lineLimit(2...5)
                            .focused($describeFocused)
                            .submitLabel(.done)
                        Button {
                            Task { await analyzeDescription() }
                        } label: {
                            HStack {
                                if analyzing { ProgressView() } else { Image(systemName: "sparkles") }
                                Text(analyzing ? "Working it out…" : (confidence == nil ? "Fill in with AI" : "Fill in again"))
                            }
                        }
                        .disabled(analyzing || mealText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("Describe what you ate")
                    } footer: {
                        if analysisError != nil || confidence != nil {
                            analysisFooter
                        } else {
                            Text("Tip: tap the microphone on the keyboard to say it instead. Amounts help, e.g. \"150g rice\" or \"a large bowl\". Or skip this and type the numbers below.")
                        }
                    }
                    .themedRows()
                }

                Section("Meal") {
                    TextField("Name", text: $name)
                    DatePicker("Time", selection: $date)
                }
                .themedRows()

                Section("Nutrition") {
                    numberRow("Calories", value: $calories, unit: "kcal")
                    numberRow("Protein", value: $protein, unit: "g")
                    numberRow("Carbs", value: $carbs, unit: "g")
                    numberRow("Fat", value: $fat, unit: "g")
                }
                .themedRows()

                Section {
                    Toggle(isOn: $isFavorite) {
                        Label("Save as favourite", systemImage: isFavorite ? "star.fill" : "star")
                    }
                } footer: {
                    Text("Favourites appear in Quick add on the Today tab, so you can log them again with one tap.")
                }
                .themedRows()

                if !notes.isEmpty || existing != nil {
                    Section("Notes") {
                        TextField("Notes", text: $notes, axis: .vertical)
                    }
                    .themedRows()
                }
            }
            .themedList()
            .navigationTitle(existing == nil ? "Add meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || analyzing)
                }
            }
            .onAppear {
                if let originalName {
                    isFavorite = MealLogger.favorite(named: originalName, context: modelContext) != nil
                }
                if isBlankNewMeal { describeFocused = true }
            }
            .task {
                // Start analysing straight away for a new photo, if a key is set.
                if let image, existing == nil, originalName == nil, confidence == nil, Keychain.apiKey != nil {
                    await analyze(image)
                }
            }
        }
    }

    @ViewBuilder
    private var analysisFooter: some View {
        if let analysisError {
            Text(analysisError).foregroundStyle(.red)
        } else if let confidence {
            Text("AI confidence: \(confidence). \(notes.isEmpty ? "" : notes + " ")Check the numbers and adjust anything that looks off.")
        }
    }

    private func numberRow(_ label: String, value: Binding<Double>, unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number.precision(.fractionLength(0)))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 90)
            Text(unit).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
        }
    }

    // MARK: AI

    private func analyze(_ image: UIImage) async {
        await runAnalysis { try await $0.analyzeMeal(image: image, hint: hint) }
    }

    private func analyzeDescription() async {
        describeFocused = false
        let text = mealText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        await runAnalysis { try await $0.analyzeText(text) }
    }

    private func runAnalysis(_ call: (ClaudeService) async throws -> MealAnalysis) async {
        analyzing = true
        analysisError = nil
        defer { analyzing = false }
        do {
            let result = try await call(ClaudeService.fromSettings())
            name = result.name
            calories = result.calories.rounded()
            protein = result.protein.rounded()
            carbs = result.carbs.rounded()
            fat = result.fat.rounded()
            notes = result.notes
            confidence = result.confidence
        } catch {
            analysisError = error.localizedDescription
        }
    }

    // MARK: Save

    private func save() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let macros = Macros(calories: calories, protein: protein, carbs: carbs, fat: fat)
        let photo = image?.preparedForUpload(maxDimension: 600, quality: 0.6)

        if let existing {
            existing.name = trimmedName
            existing.date = date
            existing.calories = calories
            existing.protein = protein
            existing.carbs = carbs
            existing.fat = fat
            existing.notes = notes
            if saveToHealth {
                // Replace the old Health entries with the edited values.
                health.deleteMeal(id: existing.id)
                await health.saveMeal(id: existing.id, name: trimmedName, date: date, macros: macros)
            }
        } else {
            await MealLogger.log(MealDraft(name: trimmedName, macros: macros, photo: photo),
                                 at: date,
                                 notes: notes,
                                 context: modelContext,
                                 health: health)
        }

        updateFavorite(name: trimmedName, macros: macros, photo: photo)
        dismiss()
    }

    /// Adds or removes the favourite to match the toggle. An existing favourite keeps its
    /// original portion, so adjusting a one-off meal doesn't change it.
    private func updateFavorite(name: String, macros: Macros, photo: Data?) {
        let current = MealLogger.favorite(named: originalName ?? name, context: modelContext)
            ?? MealLogger.favorite(named: name, context: modelContext)
        if isFavorite, current == nil {
            modelContext.insert(FavoriteMeal(name: name, macros: macros, photo: photo))
        } else if !isFavorite, let current {
            modelContext.delete(current)
        }
    }
}
