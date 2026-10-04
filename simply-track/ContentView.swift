//
//  ContentView.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(PersistenceStatus.self) private var persistenceStatus
    @Query private var profiles: [UserProfile]
    @Query(sort: \FoodEntry.consumedAt, order: .reverse) private var entries: [FoodEntry]
    @Query(sort: \FoodCatalogItem.name) private var foodCatalog: [FoodCatalogItem]

    @State private var showingAddEntrySheet = false
    @State private var showingQuickStartSheet = false
    @State private var dailyActiveCaloriesBurned: Double = 0
    @State private var weeklyActiveCaloriesBurned: Double = 0
    @State private var activeCaloriesFallbackMessage: String = ""
    @StateObject private var syncCoordinator = HealthKitSyncCoordinator()
    private let reminderManager = ReminderManager()

    private var profile: UserProfile {
        if let existing = profiles.first {
            return existing
        }

        let fallbackProfile = UserProfile()
        modelContext.insert(fallbackProfile)
        return fallbackProfile
    }

    var body: some View {
        ZStack(alignment: .top) {
            TabView {
            NavigationViewWrapper {
                HomeDashboardView(
                    entries: entries,
                    includeActiveCaloriesInMax: profile.includeActiveCaloriesInMax,
                    dailyActiveCaloriesBurned: dailyActiveCaloriesBurned,
                    weeklyActiveCaloriesBurned: weeklyActiveCaloriesBurned,
                    activeCaloriesFallbackMessage: activeCaloriesFallbackMessage,
                    syncMessage: syncCoordinator.syncMessage,
                    hasCompletedQuickStart: profile.hasCompletedQuickStart,
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
                    },
                    hasHealthKitAccess: syncCoordinator.hasHealthKitAccess
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            }
            
            // Show persistence error banner if needed
            if let error = persistenceStatus.error {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: persistenceStatus.isCloudKitQuotaError ? "icloud.slash" : "exclamationmark.circle.fill")
                            .foregroundStyle(persistenceStatus.isCloudKitQuotaError ? .orange : .red)
                            .font(.title3)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(error.errorDescription ?? "Storage Error")
                                .font(.headline)
                            if persistenceStatus.mode == .localOnly {
                                Text("Using local storage only—changes will not sync to iCloud.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if persistenceStatus.mode == .inMemoryOnly {
                                Text("The app is currently using temporary in-memory storage, so changes will be lost when the app closes.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    
                    if persistenceStatus.isCloudKitQuotaError {
                        Text("Free up iCloud storage space and relaunch the app to re-enable CloudKit sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if persistenceStatus.mode == .inMemoryOnly {
                        Text("Please restart the app after checking iCloud/account settings or contact support if the problem continues.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .border(Color(.systemGray4))
            }
        }
        .sheet(isPresented: $showingAddEntrySheet) {
            AddFoodEntrySheet(foodCatalog: foodCatalog, initialSaveToCatalog: profile.autoSaveToCatalog) { payload in
                addEntry(payload)
            }
        }
        .sheet(isPresented: $showingQuickStartSheet) {
            quickStartSheet
        }
        .task {
            migrateLegacyPreferencesIntoProfileIfNeeded()
            bootstrapIfNeeded()
            await refreshHealthDataForCurrentPreferences()
        }
        .onChange(of: profile.enableReminders) { _, enabled in
            Task {
                await updateReminderSchedule(enabled: enabled)
            }
        }
        .onChange(of: profile.useHealthSync) { _, enabled in
            Task {
                if enabled {
                    await refreshHealthDataForCurrentPreferences()
                } else {
                    clearActiveCaloriesState()
                }
            }
        }
        .onChange(of: profile.includeActiveCaloriesInMax) { _, enabled in
            guard enabled else {
                clearActiveCaloriesState()
                return
            }

            Task {
                guard profile.useHealthSync else { return }
                await refreshActiveCaloriesBurned()
            }
        }
    }

    private func migrateLegacyPreferencesIntoProfileIfNeeded() {
        let defaults = UserDefaults.standard
        let markerKey = "didMigratePreferencesToUserProfileV1"

        guard defaults.bool(forKey: markerKey) == false else {
            return
        }

        if let value = defaults.object(forKey: "hasCompletedQuickStart") as? Bool {
            profile.hasCompletedQuickStart = value
        }
        if let value = defaults.object(forKey: "useHealthSync") as? Bool {
            profile.useHealthSync = value
        } else if let value = defaults.object(forKey: "useCloudKitSync") as? Bool {
            profile.useHealthSync = value
        }
        if let value = defaults.object(forKey: "enableReminders") as? Bool {
            profile.enableReminders = value
        }
        if let value = defaults.object(forKey: "includeActiveCaloriesInMax") as? Bool {
            profile.includeActiveCaloriesInMax = value
        }
        if let value = defaults.object(forKey: "autoSaveToCatalog") as? Bool {
            profile.autoSaveToCatalog = value
        }

        defaults.set(true, forKey: markerKey)
    }

    private var quickStartSheet: some View {
        QuickStartOnboardingView(
            useHealthSync: Binding(
                get: { profile.useHealthSync },
                set: { profile.useHealthSync = $0 }
            ),
            enableReminders: Binding(
                get: { profile.enableReminders },
                set: { profile.enableReminders = $0 }
            ),
            onRequestHealthKit: {
                await authorizeAndSyncHealthKit()
            },
            onComplete: {
                profile.hasCompletedQuickStart = true
                showingQuickStartSheet = false
            }
        )
    }

    private func authorizeAndSyncHealthKit() async {
        guard profile.useHealthSync else {
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
            await updateReminderSchedule(enabled: profile.enableReminders)
        }
    }

    private func refreshFromHealthKit() async {
        guard profile.useHealthSync else {
            clearActiveCaloriesState()
            return
        }

        // Pull a short lookback window (not just "today") so entries logged directly in
        // the Health app on previous days (e.g. yesterday) are reflected locally even if
        // this app wasn't opened on those days. LogEntriesView shows Today + Yesterday,
        // so we need at least 2 days of history available locally on every launch.
        let lookbackDays = 2
        let todayStart = Calendar.current.startOfDay(for: .now)
        let startDate = Calendar.current.date(byAdding: .day, value: -lookbackDays, to: todayStart) ?? todayStart
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

        if profile.includeActiveCaloriesInMax {
            await refreshActiveCaloriesBurned()
        } else {
            clearActiveCaloriesState()
        }
    }

    private func refreshActiveCaloriesBurned() async {
        guard profile.useHealthSync, profile.includeActiveCaloriesInMax else {
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
        guard profile.useHealthSync else { return }
        await syncEntriesWithHealthKit(entries.map(CalorieEntryPayload.init))
    }

    private func syncEntriesWithHealthKit(_ snapshots: [CalorieEntryPayload]) async {
        guard profile.useHealthSync else { return }
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
        guard profile.useHealthSync else {
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
