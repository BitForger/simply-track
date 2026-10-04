//
//  SettingsView.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData
#if canImport(WebKit)
import WebKit
#endif

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodCatalogItem.name) private var foodCatalog: [FoodCatalogItem]
    @Query(sort: \FoodEntry.consumedAt, order: .reverse) private var entries: [FoodEntry]

    @State private var showingHealthImportSheet = false
    @State private var isLoadingHealthImportCandidates = false
    @State private var healthImportStatusMessage: String?
    @State private var healthImportCandidates: [HealthImportCandidate] = []
    private let healthKitService = HealthKitService()
    let onOpenQuickStart: () -> Void
    let onRequestHealthKit: () async -> Void
    let hasHealthKitAccess: Bool

    init(
        onOpenQuickStart: @escaping () -> Void,
        onRequestHealthKit: @escaping () async -> Void,
        hasHealthKitAccess: Bool
    ) {
        self.onOpenQuickStart = onOpenQuickStart
        self.onRequestHealthKit = onRequestHealthKit
        self.hasHealthKitAccess = hasHealthKitAccess
    }

    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }

        let fallbackProfile = UserProfile()
        modelContext.insert(fallbackProfile)
        return fallbackProfile
    }

    @State private var isAgeExpanded = false
    @State private var isHeightExpanded = false
    @State private var isWeightExpanded = false
    @State private var dailyTargetInput: String = ""
    @State private var weeklyTargetInput: String = ""
    @FocusState private var focusedTargetField: TargetField?

    private struct ActivityLevel: Identifiable {
        let id: String
        let title: String
        let multiplier: Double
    }

    private let activityLevels: [ActivityLevel] = [
        ActivityLevel(id: "sedentary", title: "Sedentary", multiplier: 1.2),
        ActivityLevel(id: "lightlyActive", title: "Lightly Active", multiplier: 1.375),
        ActivityLevel(id: "moderatelyActive", title: "Moderately Active", multiplier: 1.55),
        ActivityLevel(id: "veryActive", title: "Very Active", multiplier: 1.725),
        ActivityLevel(id: "extraActive", title: "Extra Active", multiplier: 1.9)
    ]

    private var selectedActivityLevelID: Binding<String> {
        Binding(
            get: {
                let closest = activityLevels.min {
                    abs($0.multiplier - profile.activityMultiplier) < abs($1.multiplier - profile.activityMultiplier)
                }
                return closest?.id ?? activityLevels[0].id
            },
            set: { newID in
                guard let selected = activityLevels.first(where: { $0.id == newID }) else { return }
                profile.activityMultiplier = selected.multiplier
            }
        )
    }

    private var dailyTargetTextBinding: Binding<String> {
        Binding(
            get: { dailyTargetInput },
            set: { dailyTargetInput = sanitizeTargetInput($0) }
        )
    }

    private var weeklyTargetTextBinding: Binding<String> {
        Binding(
            get: { weeklyTargetInput },
            set: { weeklyTargetInput = sanitizeTargetInput($0) }
        )
    }

    private var burnAdjustmentMultiplier: Double {
        profile.nutritionGoal == .loseWeight ? 0.8 : 1.0
    }

    private var burnAdjustmentSummary: String {
        let percent = Int((burnAdjustmentMultiplier * 100).rounded())
        return "Adjusted max = base target + \(percent)% of active calories burned (today/week so far)."
    }

    private var personalCatalog: [FoodCatalogItem] {
        foodCatalog.filter { $0.isUserAdded }
    }

    private var localHealthImportCandidates: [HealthImportCandidate] {
        let healthKitEntries = entries.filter { $0.source == "healthKit" }
        var latestByName: [String: FoodEntry] = [:]

        for entry in healthKitEntries {
            let key = normalizedHealthImportKey(entry.foodName)
            if let existing = latestByName[key], existing.consumedAt >= entry.consumedAt {
                continue
            }
            latestByName[key] = entry
        }

        return latestByName.values
            .filter { entry in
                !foodCatalog.contains { $0.name.caseInsensitiveCompare(entry.foodName) == .orderedSame }
            }
            .map { HealthImportCandidate(name: $0.foodName, amountDescription: $0.amountDescription, calories: $0.calories) }
            .sorted { $0.name < $1.name }
    }

    private var canImportFoodsFromHealth: Bool {
        hasHealthKitAccess && !isLoadingHealthImportCandidates
    }

    var body: some View {
        Form {
            Section("Privacy & Sync") {
                Toggle("Enable Health sync", isOn: Binding(
                    get: { profile.useHealthSync },
                    set: { profile.useHealthSync = $0 }
                ))
                Toggle("Enable reminders", isOn: Binding(
                    get: { profile.enableReminders },
                    set: { profile.enableReminders = $0 }
                ))
                if !hasHealthKitAccess {
                    Button("Request HealthKit Access") {
                        Task { await onRequestHealthKit() }
                    }
                    .disabled(!profile.useHealthSync)
                }

                if !profile.useHealthSync {
                    Text("Turn on Health sync to request and use HealthKit access.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if hasHealthKitAccess {
                    Text("HealthKit access is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !profile.hasCompletedQuickStart {
                Section("Quick Start") {
                    Label(
                        profile.hasCompletedQuickStart ? "Completed" : "Not completed",
                        systemImage: profile.hasCompletedQuickStart ? "checkmark.circle.fill" : "exclamationmark.circle"
                    )
                    Button("Open Quick Start") {
                        onOpenQuickStart()
                    }
                }
            }

            Section("Profile") {
                Picker(
                    "Biological Sex",
                    selection: Binding(
                        get: { profile.biologicalSex },
                        set: { profile.biologicalSex = $0 }
                    )
                ) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.rawValue.capitalized).tag(sex)
                    }
                }

                Button {
                    toggleExpandedPicker(.age)
                } label: {
                    HStack {
                        Text("Age")
                        Spacer()
                        Text("\(profile.age) years")
                            .foregroundStyle(.secondary)
                        Image(systemName: isAgeExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isAgeExpanded {
                    Picker("Age", selection: Binding(
                        get: { profile.age },
                        set: { profile.age = $0 }
                    )) {
                        ForEach(13...100, id: \.self) { age in
                            Text("\(age) years").tag(age)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Button {
                    toggleExpandedPicker(.height)
                } label: {
                    HStack {
                        Text("Height")
                        Spacer()
                        Text("\(Int(profile.heightCm.rounded())) cm")
                            .foregroundStyle(.secondary)
                        Image(systemName: isHeightExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isHeightExpanded {
                    Picker("Height", selection: Binding(
                        get: { Int(profile.heightCm.rounded()) },
                        set: { profile.heightCm = Double($0) }
                    )) {
                        ForEach(120...230, id: \.self) { height in
                            Text("\(height) cm").tag(height)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Button {
                    toggleExpandedPicker(.weight)
                } label: {
                    HStack {
                        Text("Weight")
                        Spacer()
                        Text("\(Int(profile.weightKg.rounded())) kg")
                            .foregroundStyle(.secondary)
                        Image(systemName: isWeightExpanded ? "chevron.up" : "chevron.down")
                            .foregroundStyle(.tertiary)
                    }
                }
                .buttonStyle(.plain)

                if isWeightExpanded {
                    Picker("Weight", selection: Binding(
                        get: { Int(profile.weightKg.rounded()) },
                        set: { profile.weightKg = Double($0) }
                    )) {
                        ForEach(35...250, id: \.self) { weight in
                            Text("\(weight) kg").tag(weight)
                        }
                    }
                    .pickerStyle(.wheel)
                    .labelsHidden()
                    .frame(height: 120)
                }

                Picker("Activity Level", selection: selectedActivityLevelID) {
                    ForEach(activityLevels) { level in
                        Text("\(level.title) (\(level.multiplier.formatted(.number.precision(.fractionLength(3)))))")
                            .tag(level.id)
                    }
                }
            }
            Section("Metabolism") {
                NavigationLink {
                    TDEEEquationSettingsView(profile: profile)
                } label: {
                    LabeledContent("TDEE Equation") {
                        Text(profile.tdeeEquation.title)
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Estimated BMR: \(Int(profile.estimatedBMR())) cal/day")
                Text("Estimated TDEE: \(Int(profile.estimatedTDEE())) cal/day")
                    .foregroundStyle(.secondary)
            }
            Section("Targets") {
                Toggle("Adjust max with active calories burned", isOn: Binding(
                    get: { profile.includeActiveCaloriesInMax },
                    set: { profile.includeActiveCaloriesInMax = $0 }
                ))

                Text(burnAdjustmentSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Picker(
                    "Goal",
                    selection: Binding(
                        get: { profile.nutritionGoal },
                        set: { profile.nutritionGoal = $0 }
                    )
                ) {
                    ForEach(NutritionGoal.allCases) { goal in
                        Text(goal.title).tag(goal)
                    }
                }

                if profile.nutritionGoal == .loseWeight {
                    Picker(
                        "Weekly loss pace",
                        selection: Binding(
                            get: { profile.weightLossPace },
                            set: { profile.weightLossPace = $0 }
                        )
                    ) {
                        ForEach(WeightLossPace.allCases) { pace in
                            Text(pace.title).tag(pace)
                        }
                    }
                }

                LabeledContent("Recommended daily") {
                    Text("\(Int(profile.recommendedDailyTarget())) cal")
                        .foregroundStyle(.secondary)
                }

                LabeledContent("Recommended weekly") {
                    Text("\(Int(profile.recommendedWeeklyTarget())) cal")
                        .foregroundStyle(.secondary)
                }

                Button("Use Recommended Targets") {
                    profile.dailyCalorieTarget = profile.recommendedDailyTarget()
                    profile.weeklyCalorieTarget = profile.recommendedWeeklyTarget()
                    dailyTargetInput = formattedCalories(profile.dailyCalorieTarget)
                    weeklyTargetInput = formattedCalories(profile.weeklyCalorieTarget)
                    commitProfileChanges()
                }

                LabeledContent("Daily target") {
                    HStack(spacing: 8) {
                        TextField("2,000", text: dailyTargetTextBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedTargetField, equals: .daily)
                            .frame(width: 100)
                        Text("cal")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Weekly target") {
                    HStack(spacing: 8) {
                        TextField("14,000", text: weeklyTargetTextBinding)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .focused($focusedTargetField, equals: .weekly)
                            .frame(width: 100)
                        Text("cal")
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Personal Foods") {
                Toggle("Auto-save manual entries", isOn: Binding(
                    get: { profile.autoSaveToCatalog },
                    set: { profile.autoSaveToCatalog = $0 }
                ))
                Text("New foods you log manually are saved to your Quick Pick list for fast re-entry.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button {
                    Task {
                        await loadHealthImportCandidates()
                    }
                } label: {
                    HStack(spacing: 8) {
                        if isLoadingHealthImportCandidates {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(isLoadingHealthImportCandidates ? "Loading Health foods…" : "Import Foods from Health")
                    }
                }
                .disabled(!canImportFoodsFromHealth)

                if let healthImportStatusMessage {
                    Text(healthImportStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if personalCatalog.isEmpty {
                    Text("No personal foods yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(personalCatalog) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.name)
                                Text(item.defaultAmountDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(Int(item.caloriesPerDefaultAmount)) cal")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete(perform: deletePersonalCatalogItems)
                }
            }

            Button("Support the developer", systemImage: "heart") {
                if let url = URL(string: "https://ko-fi.com/bitforger") {
                    openURL(url)
                }
            }
        }
        .sheet(isPresented: $showingHealthImportSheet) {
            HealthKitCatalogImportSheet(candidates: healthImportCandidates) { selected in
                importCatalogItems(selected)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isAgeExpanded)
        .animation(.easeInOut(duration: 0.2), value: isHeightExpanded)
        .animation(.easeInOut(duration: 0.2), value: isWeightExpanded)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if focusedTargetField != nil {
                    Button("Done") {
                        commitTargetFieldEdits()
                        focusedTargetField = nil
                    }
                }
            }
        }
        .onAppear {
            dailyTargetInput = formattedCalories(profile.dailyCalorieTarget)
            weeklyTargetInput = formattedCalories(profile.weeklyCalorieTarget)
        }
        .onChange(of: focusedTargetField) { oldValue, newValue in
            if oldValue != nil && newValue == nil {
                commitTargetFieldEdits()
            }
            if newValue == .daily {
                dailyTargetInput = sanitizeTargetInput(dailyTargetInput)
            }
            if newValue == .weekly {
                weeklyTargetInput = sanitizeTargetInput(weeklyTargetInput)
            }
        }
        .onChange(of: profile.dailyCalorieTarget) { _, newValue in
            if focusedTargetField != .daily {
                dailyTargetInput = formattedCalories(newValue)
            }
        }
        .onChange(of: profile.weeklyCalorieTarget) { _, newValue in
            if focusedTargetField != .weekly {
                weeklyTargetInput = formattedCalories(newValue)
            }
        }
        .onChange(of: profile.age) { _, _ in commitProfileChanges() }
        .onChange(of: profile.heightCm) { _, _ in commitProfileChanges() }
        .onChange(of: profile.weightKg) { _, _ in commitProfileChanges() }
        .onChange(of: profile.activityMultiplier) { _, _ in commitProfileChanges() }
        .onChange(of: profile.biologicalSex) { _, _ in commitProfileChanges() }
        .onChange(of: profile.nutritionGoal) { _, _ in commitProfileChanges() }
        .onChange(of: profile.weightLossPace) { _, _ in commitProfileChanges() }
        .onChange(of: profile.includeActiveCaloriesInMax) { _, _ in commitProfileChanges() }
        .onChange(of: profile.useHealthSync) { _, _ in commitProfileChanges() }
        .onChange(of: profile.enableReminders) { _, _ in commitProfileChanges() }
        .onChange(of: profile.autoSaveToCatalog) { _, _ in commitProfileChanges() }
        .navigationTitle("Settings")
        
    }

    private enum ExpandedPickerField {
        case age
        case height
        case weight
    }

    private enum TargetField {
        case daily
        case weekly
    }

    private func toggleExpandedPicker(_ field: ExpandedPickerField) {
        withAnimation {
            switch field {
            case .age:
                isAgeExpanded.toggle()
                if isAgeExpanded {
                    isHeightExpanded = false
                    isWeightExpanded = false
                }
            case .height:
                isHeightExpanded.toggle()
                if isHeightExpanded {
                    isAgeExpanded = false
                    isWeightExpanded = false
                }
            case .weight:
                isWeightExpanded.toggle()
                if isWeightExpanded {
                    isAgeExpanded = false
                    isHeightExpanded = false
                }
            }
        }
    }

    private func commitTargetFieldEdits() {
        let dailyDigits = sanitizeTargetInput(dailyTargetInput)
        if let daily = Int(dailyDigits) {
            let clampedDaily = min(max(Double(daily), 800), 6000)
            profile.dailyCalorieTarget = clampedDaily
            dailyTargetInput = formattedCalories(clampedDaily)
        } else {
            dailyTargetInput = formattedCalories(profile.dailyCalorieTarget)
        }

        let weeklyDigits = sanitizeTargetInput(weeklyTargetInput)
        if let weekly = Int(weeklyDigits) {
            let clampedWeekly = min(max(Double(weekly), 5600), 42000)
            profile.weeklyCalorieTarget = clampedWeekly
            weeklyTargetInput = formattedCalories(clampedWeekly)
        } else {
            weeklyTargetInput = formattedCalories(profile.weeklyCalorieTarget)
        }
        
        // Explicitly save critical profile changes
        commitProfileChanges()
    }

    private func commitProfileChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Warning: Failed to save profile changes: \(error)")
            // App continues; SwiftData will attempt to save on next opportunity
        }
    }

    private func deletePersonalCatalogItems(offsets: IndexSet) {
        let idsToDelete = offsets.map { personalCatalog[$0].id }
        for item in foodCatalog where idsToDelete.contains(item.id) {
            modelContext.delete(item)
        }
    }

    @MainActor private func loadHealthImportCandidates() async {
        guard hasHealthKitAccess else {
            healthImportStatusMessage = "Request HealthKit access first."
            return
        }

        isLoadingHealthImportCandidates = true
        healthImportStatusMessage = nil

        defer {
            isLoadingHealthImportCandidates = false
        }

        let startDate = Calendar.current.date(byAdding: .year, value: -5, to: .now) ?? .distantPast
        let fetchedPayloads = await fetchHealthEntries(from: startDate, to: .now)
        let importedCandidates = makeHealthImportCandidates(from: fetchedPayloads)
        let fallbackCandidates = importedCandidates.isEmpty ? localHealthImportCandidates : importedCandidates

        healthImportCandidates = fallbackCandidates

        if fallbackCandidates.isEmpty {
            healthImportStatusMessage = "No importable foods were found in Health."
            showingHealthImportSheet = false
        } else {
            healthImportStatusMessage = importedCandidates.isEmpty
                ? "Loaded previously synced Health entries."
                : nil
            showingHealthImportSheet = true
        }
    }

    private func fetchHealthEntries(from startDate: Date, to endDate: Date) async -> [CalorieEntryPayload] {
        do {
            return try await healthKitService.fetchEntries(from: startDate, to: endDate)
        } catch {
            return []
        }
    }

    private func makeHealthImportCandidates(from payloads: [CalorieEntryPayload]) -> [HealthImportCandidate] {
        var latestByName: [String: CalorieEntryPayload] = [:]

        for payload in payloads {
            let key = normalizedHealthImportKey(payload.foodName)
            guard !key.isEmpty else { continue }

            if let existing = latestByName[key], existing.consumedAt >= payload.consumedAt {
                continue
            }
            latestByName[key] = payload
        }

        return latestByName.values
            .filter { entry in
                !foodCatalog.contains { existing in
                    normalizedHealthImportKey(existing.name) == normalizedHealthImportKey(entry.foodName)
                }
            }
            .map { HealthImportCandidate(name: $0.foodName, amountDescription: $0.amountDescription, calories: $0.calories) }
            .sorted { $0.name < $1.name }
    }

    private func normalizedHealthImportKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func importCatalogItems(_ candidates: [HealthImportCandidate]) {
        for candidate in candidates {
            modelContext.insert(
                FoodCatalogItem(
                    name: candidate.name,
                    defaultAmountDescription: candidate.amountDescription,
                    caloriesPerDefaultAmount: candidate.calories,
                    isUserAdded: true
                )
            )
        }
    }

    private func sanitizeTargetInput(_ input: String) -> String {
        input.filter(\.isNumber)
    }

    private func formattedCalories(_ value: Double) -> String {
        Self.calorieNumberFormatter.string(from: NSNumber(value: Int(value.rounded()))) ?? "\(Int(value.rounded()))"
    }

    private static let calorieNumberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = Locale.current.groupingSeparator
        formatter.usesGroupingSeparator = true
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

#Preview {
    NavigationStack {
        SettingsView(
            onOpenQuickStart: {},
                onRequestHealthKit: {},
                hasHealthKitAccess: false
        )
    }
    .modelContainer(for: [UserProfile.self], inMemory: true)
}

private struct HealthImportCandidate: Identifiable {
    var id: String { name.lowercased() }
    let name: String
    let amountDescription: String
    let calories: Double
}

private struct HealthKitCatalogImportSheet: View {
    @Environment(\.dismiss) private var dismiss

    let candidates: [HealthImportCandidate]
    let onImport: ([HealthImportCandidate]) -> Void

    @State private var selectedIDs: Set<String> = []

    var body: some View {
        NavigationStack {
            List(candidates) { candidate in
                Button {
                    toggleSelection(candidate)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(candidate.name)
                            Text(candidate.amountDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(candidate.calories)) cal")
                            .foregroundStyle(.secondary)
                        Image(systemName: selectedIDs.contains(candidate.id) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedIDs.contains(candidate.id) ? .blue : .secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if candidates.isEmpty {
                    Text("No new foods found from Health history.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Import from Health")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") {
                        onImport(candidates.filter { selectedIDs.contains($0.id) })
                        dismiss()
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
    }

    private func toggleSelection(_ candidate: HealthImportCandidate) {
        if selectedIDs.contains(candidate.id) {
            selectedIDs.remove(candidate.id)
        } else {
            selectedIDs.insert(candidate.id)
        }
    }
}
