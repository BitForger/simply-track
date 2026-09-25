//
//  ContentView.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData
import Combine
import UserNotifications
#if canImport(HealthKit)
import HealthKit
#endif

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FoodEntry.consumedAt, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \FoodCatalogItem.name) private var foodCatalog: [FoodCatalogItem]

    @State private var showingAddEntrySheet = false
    @State private var showingQuickStartSheet = false
    @State private var dailyActiveCaloriesBurned: Double = 0
    @State private var weeklyActiveCaloriesBurned: Double = 0
    @State private var activeCaloriesFallbackMessage: String = ""
    @StateObject private var syncCoordinator = HealthKitSyncCoordinator()
    private let reminderManager = ReminderManager()

    @AppStorage("hasCompletedQuickStart") private var hasCompletedQuickStart = false
    @AppStorage("useHealthSync") private var useHealthSync = true
    @AppStorage("enableReminders") private var enableReminders = false
    @AppStorage("includeActiveCaloriesInMax") private var includeActiveCaloriesInMax = false
    @AppStorage("autoSaveToCatalog") private var autoSaveToCatalog = true

    var body: some View {
        TabView {
            NavigationViewWrapper {
                HomeDashboardView(
                    entries: entries,
                    includeActiveCaloriesInMax: includeActiveCaloriesInMax,
                    dailyActiveCaloriesBurned: dailyActiveCaloriesBurned,
                    weeklyActiveCaloriesBurned: weeklyActiveCaloriesBurned,
                    activeCaloriesFallbackMessage: activeCaloriesFallbackMessage,
                    syncMessage: syncCoordinator.syncMessage,
                    hasCompletedQuickStart: hasCompletedQuickStart,
                    onOpenQuickStart: { showingQuickStartSheet = true }
                )
            }
            .tabItem {
                Label("Home", systemImage: "house")
            }

            NavigationViewWrapper {
                LogEntriesView(
                    entries: entries,
                    onAddEntry: { showingAddEntrySheet = true },
                    onDeleteEntries: deleteEntries,
                    onEditEntry: updateEntry
                )
            }
            .tabItem {
                Label("Log", systemImage: "list.bullet")
            }

            NavigationViewWrapper {
                SettingsView(
                    onOpenQuickStart: { showingQuickStartSheet = true },
                    onRequestHealthKit: {
                        await authorizeAndSyncHealthKit()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .sheet(isPresented: $showingAddEntrySheet) {
            AddFoodEntrySheet(foodCatalog: foodCatalog, initialSaveToCatalog: autoSaveToCatalog) { payload in
                addEntry(payload)
            }
        }
        .sheet(isPresented: $showingQuickStartSheet) {
            quickStartSheet
        }
        .task {
            migrateLegacyHealthSyncPreferenceIfNeeded()
            bootstrapIfNeeded()
            await refreshHealthDataForCurrentPreferences()
        }
        .onChange(of: enableReminders) { _, enabled in
            Task {
                await updateReminderSchedule(enabled: enabled)
            }
        }
        .onChange(of: useHealthSync) { _, enabled in
            Task {
                if enabled {
                    await refreshHealthDataForCurrentPreferences()
                } else {
                    clearActiveCaloriesState()
                }
            }
        }
        .onChange(of: includeActiveCaloriesInMax) { _, enabled in
            guard enabled else {
                clearActiveCaloriesState()
                return
            }

            Task {
                guard useHealthSync else { return }
                await refreshActiveCaloriesBurned()
            }
        }
    }

    private func migrateLegacyHealthSyncPreferenceIfNeeded() {
        let defaults = UserDefaults.standard
        let newKey = "useHealthSync"
        let legacyKey = "useCloudKitSync"

        guard defaults.object(forKey: newKey) == nil,
              let legacyValue = defaults.object(forKey: legacyKey) as? Bool else {
            return
        }

        defaults.set(legacyValue, forKey: newKey)
        useHealthSync = legacyValue
    }

    private var quickStartSheet: some View {
        QuickStartOnboardingView(
            useHealthSync: $useHealthSync,
            enableReminders: $enableReminders,
            onRequestHealthKit: {
                await authorizeAndSyncHealthKit()
            },
            onComplete: {
                hasCompletedQuickStart = true
                showingQuickStartSheet = false
            }
        )
    }

    private func authorizeAndSyncHealthKit() async {
        guard useHealthSync else {
            syncCoordinator.syncMessage = "Enable Health sync in Settings before requesting HealthKit access."
            return
        }

        await syncCoordinator.requestAuthorization()
        await refreshFromHealthKit()
        await syncAllEntriesWithHealthKit()
    }

    @MainActor private func addEntry(_ payload: AddFoodEntryPayload) {
        let entry = FoodEntry(
            foodName: payload.foodName,
            amountDescription: payload.amountDescription,
            calories: payload.calories,
            consumedAt: payload.consumedAt,
            updatedAt: .now,
            source: "manual"
        )

        withAnimation {
            modelContext.insert(entry)
        }

        if payload.saveToCatalog {
            upsertPersonalCatalogItem(
                name: payload.foodName,
                amount: payload.amountDescription,
                calories: payload.calories
            )
        }

        let localSnapshots = deduplicatedSnapshots(entries.map(CalorieEntryPayload.init) + [CalorieEntryPayload(entry)])

        Task {
            await syncEntriesWithHealthKit(localSnapshots)
        }
    }

    private func upsertPersonalCatalogItem(name: String, amount: String, calories: Double) {
        let alreadyExists = foodCatalog.contains { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        guard !alreadyExists else { return }

        modelContext.insert(
            FoodCatalogItem(
                name: name,
                defaultAmountDescription: amount,
                caloriesPerDefaultAmount: calories,
                isUserAdded: true
            )
        )
    }

    private func deleteEntries(offsets: IndexSet) {
        let removedEntries = offsets.map { entries[$0] }

        withAnimation {
            for index in offsets {
                modelContext.delete(entries[index])
            }
        }

        Task {
            await syncCoordinator.deleteEntriesFromHealthKit(removedEntries.map(CalorieEntryPayload.init))
            await syncAllEntriesWithHealthKit()
        }
    }

    @MainActor private func updateEntry(_ entry: FoodEntry, with values: EditableFoodEntryValues) {
        entry.foodName = values.foodName
        entry.amountDescription = values.amountDescription
        entry.calories = values.calories
        entry.consumedAt = values.consumedAt
        entry.updatedAt = .now

        let snapshots = deduplicatedSnapshots(entries.map(CalorieEntryPayload.init))
        Task {
            await syncEntriesWithHealthKit(snapshots)
        }
    }

    private func bootstrapIfNeeded() {
        if foodCatalog.isEmpty {
            FoodCatalogSeed.defaults.forEach {
                modelContext.insert(
                    FoodCatalogItem(
                        name: $0.name,
                        defaultAmountDescription: $0.amount,
                        caloriesPerDefaultAmount: $0.calories,
                        isUserAdded: false
                    )
                )
            }
        }

        Task {
            await updateReminderSchedule(enabled: enableReminders)
        }
    }

    private func refreshFromHealthKit() async {
        guard useHealthSync else {
            clearActiveCaloriesState()
            return
        }

        let startDate = Calendar.current.startOfDay(for: .now)
        let payloads = await syncCoordinator.pullLatestEntries(from: startDate, to: .now)

        if !payloads.isEmpty {
            for payload in payloads {
                if let match = entries.first(where: {
                    $0.healthKitSampleIdentifier == payload.healthKitSampleIdentifier || $0.id == payload.id
                }) {
                    if payload.updatedAt >= match.updatedAt {
                        match.foodName = payload.foodName
                        match.amountDescription = payload.amountDescription
                        match.calories = payload.calories
                        match.consumedAt = payload.consumedAt
                        match.updatedAt = payload.updatedAt
                        match.healthKitSampleIdentifier = payload.healthKitSampleIdentifier
                        match.source = "healthKit"
                    }
                } else {
                    modelContext.insert(
                        FoodEntry(
                            id: payload.id,
                            foodName: payload.foodName,
                            amountDescription: payload.amountDescription,
                            calories: payload.calories,
                            consumedAt: payload.consumedAt,
                            updatedAt: payload.updatedAt,
                            source: "healthKit",
                            healthKitSampleIdentifier: payload.healthKitSampleIdentifier
                        )
                    )
                }
            }
        }

        if includeActiveCaloriesInMax {
            await refreshActiveCaloriesBurned()
        } else {
            clearActiveCaloriesState()
        }
    }

    private func refreshActiveCaloriesBurned() async {
        guard useHealthSync, includeActiveCaloriesInMax else {
            clearActiveCaloriesState()
            return
        }

        let now = Date.now
        let dailyStart = Calendar.current.startOfDay(for: now)
        let weekRange = CalorieSummaryCalculator.weekRange(for: now)

        async let dailyBurn = syncCoordinator.pullActiveCaloriesBurned(from: dailyStart, to: now)
        async let weeklyBurn = syncCoordinator.pullActiveCaloriesBurned(from: weekRange.start, to: now)

        let dailyResult = await dailyBurn
        let weeklyResult = await weeklyBurn

        dailyActiveCaloriesBurned = dailyResult.calories
        weeklyActiveCaloriesBurned = weeklyResult.calories

        let fallbackNotes = [dailyResult.fallbackNote, weeklyResult.fallbackNote]
            .compactMap { $0 }
        activeCaloriesFallbackMessage = fallbackNotes.first ?? ""
    }

    private func syncAllEntriesWithHealthKit() async {
        guard useHealthSync else { return }
        await syncEntriesWithHealthKit(entries.map(CalorieEntryPayload.init))
    }

    private func syncEntriesWithHealthKit(_ snapshots: [CalorieEntryPayload]) async {
        guard useHealthSync else { return }
        let mergedPayloads = await syncCoordinator.sync(localEntries: snapshots)

        for payload in mergedPayloads {
            if let match = entries.first(where: { $0.id == payload.id || $0.healthKitSampleIdentifier == payload.healthKitSampleIdentifier }) {
                if payload.updatedAt >= match.updatedAt {
                    match.foodName = payload.foodName
                    match.amountDescription = payload.amountDescription
                    match.calories = payload.calories
                    match.consumedAt = payload.consumedAt
                    match.updatedAt = payload.updatedAt
                    match.healthKitSampleIdentifier = payload.healthKitSampleIdentifier
                    match.source = payload.source
                }
            } else {
                modelContext.insert(
                    FoodEntry(
                        id: payload.id,
                        foodName: payload.foodName,
                        amountDescription: payload.amountDescription,
                        calories: payload.calories,
                        consumedAt: payload.consumedAt,
                        updatedAt: payload.updatedAt,
                        source: payload.source,
                        healthKitSampleIdentifier: payload.healthKitSampleIdentifier
                    )
                )
            }
        }
    }

    private func deduplicatedSnapshots(_ snapshots: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
        var byID: [UUID: CalorieEntryPayload] = [:]
        for snapshot in snapshots {
            if let existing = byID[snapshot.id] {
                byID[snapshot.id] = snapshot.updatedAt >= existing.updatedAt ? snapshot : existing
            } else {
                byID[snapshot.id] = snapshot
            }
        }
        return Array(byID.values)
    }

    private func refreshHealthDataForCurrentPreferences() async {
        guard useHealthSync else {
            clearActiveCaloriesState()
            return
        }

        await refreshFromHealthKit()
    }

    private func clearActiveCaloriesState() {
        dailyActiveCaloriesBurned = 0
        weeklyActiveCaloriesBurned = 0
        activeCaloriesFallbackMessage = ""
    }

    private func updateReminderSchedule(enabled: Bool) async {
        do {
            if enabled {
                try await reminderManager.enableDefaultReminder()
            } else {
                await reminderManager.disableReminder()
            }
        } catch {
            syncCoordinator.syncMessage = "Reminder setup failed: \(error.localizedDescription)"
        }
    }
}

private struct HomeDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    let entries: [FoodEntry]
    let includeActiveCaloriesInMax: Bool
    let dailyActiveCaloriesBurned: Double
    let weeklyActiveCaloriesBurned: Double
    let activeCaloriesFallbackMessage: String
    let syncMessage: String
    let hasCompletedQuickStart: Bool
    let onOpenQuickStart: () -> Void

    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }

        let fallbackProfile = UserProfile()
        modelContext.insert(fallbackProfile)
        return fallbackProfile
    }

    private var todayCalories: Double {
        CalorieSummaryCalculator.dailyTotal(from: entries, on: .now)
    }

    private var weeklyCalories: Double {
        CalorieSummaryCalculator.weeklyTotal(from: entries, around: .now)
    }

    private var burnAdjustmentMultiplier: Double {
        profile.nutritionGoal == .loseWeight ? 0.8 : 1.0
    }

    private var baseDailyTarget: Double {
        profile.dailyCalorieTarget
    }

    private var baseWeeklyTarget: Double {
        profile.weeklyCalorieTarget
    }

    private var adjustedDailyBonus: Double {
        includeActiveCaloriesInMax ? (dailyActiveCaloriesBurned * burnAdjustmentMultiplier) : 0
    }

    private var adjustedWeeklyBonus: Double {
        includeActiveCaloriesInMax ? (weeklyActiveCaloriesBurned * burnAdjustmentMultiplier) : 0
    }

    private var dailyTarget: Double {
        baseDailyTarget + adjustedDailyBonus
    }

    private var weeklyTarget: Double {
        baseWeeklyTarget + adjustedWeeklyBonus
    }

    private var weekLoggedDays: Int {
        StreakCalculator.weekLoggedDays(entries: entries, around: .now)
    }

    private var currentStreakDays: Int {
        StreakCalculator.currentDailyLoggingStreak(entries: entries)
    }

    var body: some View {
        List {
            if !hasCompletedQuickStart {
                Section("Quick Start") {
                    Text("Finish the 3-step privacy setup when you are ready.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Quick Start") {
                        onOpenQuickStart()
                    }
                }
            }

            Section("Today") {
                dailyCard
            }

            Section("Week") {
                weeklyCard
            }

            Section("Consistency") {
                consistencyCard
            }

            Section("Targets") {
                metabolismCard
            }

            if !syncMessage.isEmpty {
                Section("Sync") {
                    Text(syncMessage)
                        .font(.footnote)
                }
            }

        }
        .navigationTitle("Simply Track")
    }

    private var dailyCard: some View {
        let progress = max(0, min(1, todayCalories / max(dailyTarget, 1)))
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(todayCalories)) / \(Int(dailyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.green)
            if includeActiveCaloriesInMax {
                Text("Base \(Int(baseDailyTarget)) + bonus \(Int(adjustedDailyBonus.rounded())) (\(Int((burnAdjustmentMultiplier * 100).rounded()))% of \(Int(dailyActiveCaloriesBurned.rounded())) burned)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Daily progress")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var weeklyCard: some View {
        let status = CalorieSummaryCalculator.weeklyStatus(total: weeklyCalories, target: weeklyTarget)
        let progress = max(0, min(1, weeklyCalories / max(weeklyTarget, 1)))
        let weekRange = CalorieSummaryCalculator.weekRange(for: .now)
        let remaining = CalorieSummaryCalculator.remainingWeeklyCalories(total: weeklyCalories, target: weeklyTarget)

        return VStack(alignment: .leading, spacing: 8) {
            Text("\(Int(weeklyCalories)) / \(Int(weeklyTarget)) cal")
                .font(.title3.weight(.semibold))
            ProgressView(value: progress)
                .tint(.blue)
            if includeActiveCaloriesInMax {
                Text("Base \(Int(baseWeeklyTarget)) + bonus \(Int(adjustedWeeklyBonus.rounded())) (\(Int((burnAdjustmentMultiplier * 100).rounded()))% of \(Int(weeklyActiveCaloriesBurned.rounded())) burned this week)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Week \(weekRange.start, format: .dateTime.month().day()) - \(weekRange.end.addingTimeInterval(-1), format: .dateTime.month().day())")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(weeklyStatusText(status))
                .font(.caption.weight(.semibold))
                .foregroundStyle(weeklyStatusColor(status))
            Text("Remaining this week: \(Int(remaining)) cal")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var consistencyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Current streak: \(currentStreakDays) day\(currentStreakDays == 1 ? "" : "s")")
            Text("Logged this week: \(weekLoggedDays) of 7 days")
            Text("Weekly adherence matters as much as daily precision.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var metabolismCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Estimated BMR: \(Int(profile.estimatedBMR())) cal/day")
            Text("Estimated TDEE: \(Int(profile.estimatedTDEE())) cal/day")
            Group {
                if includeActiveCaloriesInMax {
                    Text("Adjusted max uses base + \(Int((burnAdjustmentMultiplier * 100).rounded()))% of active calories burned so far.")
                } else {
                    Text("Adjusted max is off. Daily/weekly max uses your base targets only.")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)

            if includeActiveCaloriesInMax && !activeCaloriesFallbackMessage.isEmpty {
                Text(activeCaloriesFallbackMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func weeklyStatusText(_ status: WeeklyAggregateStatus) -> String {
        switch status {
        case .onTrack:
            return "On track this week"
        case .aboveTarget:
            return "Above weekly target"
        case .belowTarget:
            return "Below weekly target"
        }
    }

    private func weeklyStatusColor(_ status: WeeklyAggregateStatus) -> Color {
        switch status {
        case .onTrack:
            return .green
        case .aboveTarget:
            return .orange
        case .belowTarget:
            return .red
        }
    }
}

fileprivate struct NavigationViewWrapper<Content: View>: View {
    let content: () -> Content

    var body: some View {
#if os(macOS)
        NavigationSplitView {
            content()
        } detail: {
            Text("Select an item")
        }
#else
        NavigationStack {
            content()
        }
#endif
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, FoodCatalogItem.self, UserProfile.self], inMemory: true)
}

private struct AddFoodEntryPayload {
    let foodName: String
    let amountDescription: String
    let calories: Double
    let consumedAt: Date
    let saveToCatalog: Bool
}

private struct AddFoodEntrySheet: View {
    @Environment(\.dismiss) private var dismiss

    let foodCatalog: [FoodCatalogItem]
    let initialSaveToCatalog: Bool
    let onSave: (AddFoodEntryPayload) -> Void

    @State private var selectedCatalogID: UUID?
    @State private var foodName = ""
    @State private var amountDescription = ""
    @State private var caloriesText = ""
    @State private var consumedAt = Date()
    @State private var saveToCatalog: Bool

    init(foodCatalog: [FoodCatalogItem], initialSaveToCatalog: Bool, onSave: @escaping (AddFoodEntryPayload) -> Void) {
        self.foodCatalog = foodCatalog
        self.initialSaveToCatalog = initialSaveToCatalog
        self.onSave = onSave
        _saveToCatalog = State(initialValue: initialSaveToCatalog)
    }

    private var suggestedCatalog: [FoodCatalogItem] {
        foodCatalog.filter { !$0.isUserAdded }.sorted { $0.name < $1.name }
    }

    private var personalCatalog: [FoodCatalogItem] {
        foodCatalog.filter { $0.isUserAdded }.sorted { $0.name < $1.name }
    }

    var body: some View {
        NavigationStack {
            Form {
                if !foodCatalog.isEmpty {
                    Picker("Quick pick", selection: $selectedCatalogID) {
                        Text("None").tag(UUID?.none)
                        if !suggestedCatalog.isEmpty {
                            Section("Suggested") {
                                ForEach(suggestedCatalog) { item in
                                    Text(item.name).tag(UUID?.some(item.id))
                                }
                            }
                        }
                        if !personalCatalog.isEmpty {
                            Section("Your Foods") {
                                ForEach(personalCatalog) { item in
                                    Text(item.name).tag(UUID?.some(item.id))
                                }
                            }
                        }
                    }
                    .onChange(of: selectedCatalogID) { _, newValue in
                        guard let id = newValue, let item = foodCatalog.first(where: { $0.id == id }) else { return }
                        foodName = item.name
                        amountDescription = item.defaultAmountDescription
                        caloriesText = String(Int(item.caloriesPerDefaultAmount))
                    }
                }

                TextField("Food name", text: $foodName)
                TextField("Amount", text: $amountDescription)
                TextField("Calories", text: $caloriesText)
#if os(iOS)
                    .keyboardType(.decimalPad)
#endif
                DatePicker("Time", selection: $consumedAt)

                Toggle("Save to Quick Pick", isOn: $saveToCatalog)
            }
            .navigationTitle("Manual Entry")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                    }
                    .disabled(!isFormValid)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !foodName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !amountDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Double(caloriesText) != nil
    }

    private func save() {
        guard let calories = Double(caloriesText) else { return }
        onSave(
            AddFoodEntryPayload(
                foodName: foodName.trimmingCharacters(in: .whitespacesAndNewlines),
                amountDescription: amountDescription.trimmingCharacters(in: .whitespacesAndNewlines),
                calories: calories,
                consumedAt: consumedAt,
                saveToCatalog: saveToCatalog
            )
        )
        dismiss()
    }
}

private struct QuickStartOnboardingView: View {
    @Binding var useHealthSync: Bool
    @Binding var enableReminders: Bool

    let onRequestHealthKit: () async -> Void
    let onComplete: () -> Void

    @State private var step = 0

    var body: some View {
        VStack(spacing: 20) {
            Text("Quick Start")
                .font(.largeTitle.bold())

            Text("Step \(step + 1) of 3")
                .font(.headline)
                .foregroundStyle(.secondary)

            Group {
                switch step {
                case 0:
                    stepOnePrivacy
                case 1:
                    stepTwoHealthKit
                default:
                    stepThreePreferences
                }
            }

            HStack {
                Button("Back") {
                    step = max(0, step - 1)
                }
                .disabled(step == 0)

                Spacer()

                Button(step == 2 ? "Finish" : "Next") {
                    if step == 2 {
                        onComplete()
                    } else {
                        step += 1
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 8)
        }
        .padding()
    }

    private var stepOnePrivacy: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Privacy first")
                .font(.title3.weight(.semibold))
            Text("Your entries are stored locally first. You control Health sync in Settings at any time.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepTwoHealthKit: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Health integration")
                .font(.title3.weight(.semibold))
            Text("The app reads latest calorie data from Apple Health before syncing, then writes updates.")
                .foregroundStyle(.secondary)
            Button("Allow Health Access") {
                Task {
                    await onRequestHealthKit()
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var stepThreePreferences: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync preferences")
                .font(.title3.weight(.semibold))
            Toggle("Enable Health sync", isOn: $useHealthSync)
            Toggle("Enable reminders", isOn: $enableReminders)
            Text("You can change these any time later.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CalorieEntryPayload: Hashable {
    var id: UUID
    var foodName: String
    var amountDescription: String
    var calories: Double
    var consumedAt: Date
    var updatedAt: Date
    var source: String
    var healthKitSampleIdentifier: String?

    init(id: UUID = UUID(), foodName: String, amountDescription: String, calories: Double, consumedAt: Date, updatedAt: Date, source: String, healthKitSampleIdentifier: String? = nil) {
        self.id = id
        self.foodName = foodName
        self.amountDescription = amountDescription
        self.calories = calories
        self.consumedAt = consumedAt
        self.updatedAt = updatedAt
        self.source = source
        self.healthKitSampleIdentifier = healthKitSampleIdentifier
    }

    init(_ entry: FoodEntry) {
        self.init(
            id: entry.id,
            foodName: entry.foodName,
            amountDescription: entry.amountDescription,
            calories: entry.calories,
            consumedAt: entry.consumedAt,
            updatedAt: entry.updatedAt,
            source: entry.source,
            healthKitSampleIdentifier: entry.healthKitSampleIdentifier
        )
    }
}

private struct ActiveCaloriesReadResult {
    let calories: Double
    let fallbackNote: String?
}

@MainActor
private final class HealthKitSyncCoordinator: ObservableObject {
    @Published var syncMessage = ""
    private let healthKitService = HealthKitService()

    func requestAuthorization() async {
        do {
            try await healthKitService.requestAuthorization()
            syncMessage = "HealthKit access granted."
        } catch {
            syncMessage = "HealthKit authorization failed: \(error.localizedDescription)"
        }
    }

    func pullLatestEntries(from startDate: Date, to endDate: Date) async -> [CalorieEntryPayload] {
        do {
            return try await healthKitService.fetchEntries(from: startDate, to: endDate)
        } catch {
            syncMessage = "HealthKit pull failed: \(error.localizedDescription)"
            return []
        }
    }

    func deleteEntriesFromHealthKit(_ entries: [CalorieEntryPayload]) async {
        do {
            try await healthKitService.deleteEntries(entries)
        } catch {
            syncMessage = "HealthKit delete failed: \(error.localizedDescription)"
        }
    }

    func sync(localEntries: [CalorieEntryPayload]) async -> [CalorieEntryPayload] {
        do {
            let merged = try await healthKitService.syncReadFirst(localEntries: localEntries)
            syncMessage = "Last sync: \(Date.now.formatted(date: .omitted, time: .shortened))"
            return merged
        } catch {
            syncMessage = "HealthKit sync failed: \(error.localizedDescription)"
            return localEntries
        }
    }

    func pullActiveCaloriesBurned(from startDate: Date, to endDate: Date) async -> ActiveCaloriesReadResult {
        do {
            let calories = try await healthKitService.fetchActiveCaloriesBurned(from: startDate, to: endDate)
            return ActiveCaloriesReadResult(calories: calories, fallbackNote: nil)
        } catch {
            let note = "Active calories unavailable right now. Using base targets only until Health data is available."
            syncMessage = "HealthKit active calories read failed: \(error.localizedDescription)"
            return ActiveCaloriesReadResult(calories: 0, fallbackNote: note)
        }
    }
}

private actor ReminderManager {
    private let reminderIdentifier = "daily-calorie-log-reminder"

    func enableDefaultReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Log your calories"
        content.body = "A quick log now helps keep your weekly target on track."
        content.sound = .default

        var components = DateComponents()
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        try await center.add(request)
    }

    func disableReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}

private final class HealthKitService {
#if canImport(HealthKit)
    private let store = HKHealthStore()
    private let dietaryType = HKObjectType.quantityType(forIdentifier: .dietaryEnergyConsumed)!
    private let activeEnergyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!
#endif

    enum ServiceError: LocalizedError {
        case unsupported
        case authorizationUnavailable

        var errorDescription: String? {
            switch self {
            case .unsupported:
                return "HealthKit is not available on this platform."
            case .authorizationUnavailable:
                return "HealthKit permissions are unavailable."
            }
        }
    }

    func requestAuthorization() async throws {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            throw ServiceError.authorizationUnavailable
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.requestAuthorization(toShare: [dietaryType], read: [dietaryType, activeEnergyType]) { granted, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if granted {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.authorizationUnavailable)
                }
            }
        }
#else
        throw ServiceError.unsupported
#endif
    }

    func fetchActiveCaloriesBurned(from startDate: Date, to endDate: Date) async throws -> Double {
#if canImport(HealthKit)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Double, Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
            let query = HKStatisticsQuery(
                quantityType: activeEnergyType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let calories = result?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                continuation.resume(returning: calories)
            }
            store.execute(query)
        }
#else
        throw ServiceError.unsupported
#endif
    }

    func fetchEntries(from startDate: Date, to endDate: Date) async throws -> [CalorieEntryPayload] {
#if canImport(HealthKit)
        let samples = try await fetchSamples(from: startDate, to: endDate)
        return samples.map { sample in
            let metadata = sample.metadata ?? [:]
            let idString = metadata["localEntryID"] as? String
            let entryID = UUID(uuidString: idString ?? "") ?? sample.uuid
            let foodName = metadata["foodName"] as? String ?? "Health Entry"
            let amount = metadata["amount"] as? String ?? "Imported"
            let updatedAt = metadata["updatedAt"] as? Date ?? sample.endDate
            return CalorieEntryPayload(
                id: entryID,
                foodName: foodName,
                amountDescription: amount,
                calories: sample.quantity.doubleValue(for: .kilocalorie()),
                consumedAt: sample.startDate,
                updatedAt: updatedAt,
                source: "healthKit",
                healthKitSampleIdentifier: sample.uuid.uuidString
            )
        }
#else
        throw ServiceError.unsupported
#endif
    }

    func syncReadFirst(localEntries: [CalorieEntryPayload]) async throws -> [CalorieEntryPayload] {
#if canImport(HealthKit)
        guard !localEntries.isEmpty else { return [] }

        let startDate = localEntries.map(\.consumedAt).min() ?? Calendar.current.date(byAdding: .day, value: -14, to: .now) ?? .now
        let endDate = Date.now

        let remoteEntriesBeforePush = try await fetchEntries(from: startDate, to: endDate)
        let pushCandidates = entriesNeedingPush(localEntries: localEntries, remoteEntries: remoteEntriesBeforePush)
        if !pushCandidates.isEmpty {
            try await saveToHealthKit(pushCandidates)
        }
        let remoteEntriesAfterPush = try await fetchEntries(from: startDate, to: endDate)
        return merge(localEntries: localEntries, remoteEntries: remoteEntriesAfterPush)
#else
        return localEntries
#endif
    }

    func deleteEntries(_ entries: [CalorieEntryPayload]) async throws {
#if canImport(HealthKit)
        let uuids = entries
            .compactMap(\.healthKitSampleIdentifier)
            .compactMap(UUID.init(uuidString:))

        let localEntryIDPredicates = entries.map {
            HKQuery.predicateForObjects(withMetadataKey: "localEntryID", operatorType: .equalTo, value: $0.id.uuidString)
        }

        var subpredicates: [NSPredicate] = localEntryIDPredicates
        if !uuids.isEmpty {
            subpredicates.append(HKQuery.predicateForObjects(with: Set(uuids)))
        }

        guard !subpredicates.isEmpty else { return }
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: subpredicates)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.deleteObjects(of: dietaryType, predicate: predicate) { success, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.authorizationUnavailable)
                }
            }
        }
#else
        throw ServiceError.unsupported
#endif
    }

#if canImport(HealthKit)
    private func fetchSamples(from startDate: Date, to endDate: Date) async throws -> [HKQuantitySample] {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Error>) in
            let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: [])
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: dietaryType, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sort) { _, samples, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    let values = (samples as? [HKQuantitySample]) ?? []
                    continuation.resume(returning: values)
                }
            }
            store.execute(query)
        }
    }

    private func saveToHealthKit(_ entries: [CalorieEntryPayload]) async throws {
        try await deleteEntries(entries)

        let samples = entries.map { entry in
            HKQuantitySample(
                type: dietaryType,
                quantity: HKQuantity(unit: .kilocalorie(), doubleValue: entry.calories),
                start: entry.consumedAt,
                end: entry.consumedAt,
                metadata: [
                    "localEntryID": entry.id.uuidString,
                    "foodName": entry.foodName,
                    "amount": entry.amountDescription,
                    "updatedAt": entry.updatedAt
                ]
            )
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(samples) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: ServiceError.authorizationUnavailable)
                }
            }
        }
    }
#endif

    private func merge(localEntries: [CalorieEntryPayload], remoteEntries: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
        var mergedByKey: [String: CalorieEntryPayload] = [:]

        remoteEntries.forEach { remote in
            let key = mergeKey(for: remote)
            if let existing = mergedByKey[key] {
                mergedByKey[key] = remote.updatedAt >= existing.updatedAt ? remote : existing
            } else {
                mergedByKey[key] = remote
            }
        }

        for local in localEntries {
            let key = mergeKey(for: local)
            guard let remote = mergedByKey[key] else {
                mergedByKey[key] = local
                continue
            }

            if local.updatedAt > remote.updatedAt {
                mergedByKey[key] = local
            } else if local.updatedAt == remote.updatedAt {
                mergedByKey[key] = remote
            }
        }

        return Array(mergedByKey.values).sorted { $0.consumedAt > $1.consumedAt }
    }

    private func entriesNeedingPush(localEntries: [CalorieEntryPayload], remoteEntries: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
        var remoteByKey: [String: CalorieEntryPayload] = [:]
        remoteEntries.forEach { remote in
            let key = mergeKey(for: remote)
            if let existing = remoteByKey[key] {
                remoteByKey[key] = remote.updatedAt >= existing.updatedAt ? remote : existing
            } else {
                remoteByKey[key] = remote
            }
        }

        return localEntries.filter { local in
            let key = mergeKey(for: local)
            guard let remote = remoteByKey[key] else {
                return true
            }
            return local.updatedAt > remote.updatedAt
        }
    }

    private func mergeKey(for payload: CalorieEntryPayload) -> String {
        return "entry-\(payload.id.uuidString)"
    }
}
