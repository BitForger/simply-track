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

        return UserProfile()
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
            
            if let error = persistenceStatus.error {
                PersistenceStatusBannerView(error: error, status: persistenceStatus)
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

    private func authorizeAndSyncHealthKit() async -> Bool {
        guard profile.useHealthSync else {
            syncCoordinator.syncMessage = "Enable Health sync in Settings before requesting HealthKit access."
            return false
        }

        await syncCoordinator.requestAuthorization()
        guard syncCoordinator.hasHealthKitAccess else {
            profile.useHealthSync = false
            syncCoordinator.syncMessage = "HealthKit access wasn't granted. Health sync has been turned off."
            return false
        }

        await refreshFromHealthKit()
        await syncAllEntriesWithHealthKit()
        return true
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
        let status = await reminderManager.updateReminderSchedule(enabled: enabled)
        switch status {
        case .scheduled, .disabled:
            break
        case .denied:
            profile.enableReminders = false
            syncCoordinator.syncMessage = "Notifications are disabled. Enable them in Settings to use reminders."
        case .error(let error):
            profile.enableReminders = false
            syncCoordinator.syncMessage = "Reminder setup failed: \(error.localizedDescription)"
        }
    }
}



private struct PersistenceStatusBannerView: View {
    let error: PersistenceStatus.PersistenceError
    let status: PersistenceStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Image(systemName: status.isCloudKitQuotaError ? "icloud.slash" : "exclamationmark.circle.fill")
                    .foregroundStyle(status.isCloudKitQuotaError ? .orange : .red)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 4) {
                    Text(error.errorDescription ?? "Storage Error")
                        .font(.headline)
                    if status.mode == .localOnly {
                        Text("Using local storage only—changes will not sync to iCloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if status.mode == .inMemoryOnly {
                        Text("The app is currently using temporary in-memory storage, so changes will be lost when the app closes.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }

            if status.isCloudKitQuotaError {
                Text("Free up iCloud storage space and relaunch the app to re-enable CloudKit sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if status.mode == .inMemoryOnly {
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

#Preview {
    ContentView()
        .modelContainer(for: [FoodEntry.self, FoodCatalogItem.self, UserProfile.self], inMemory: true)
}
