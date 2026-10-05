//
//  HealthKitSyncCoordinator.swift
//  simply-track
//
//  Created by Noah on 10/2/26.
//

import Foundation
import Combine

@MainActor
final class HealthKitSyncCoordinator: ObservableObject {
    @Published var syncMessage: String {
        didSet {
            UserDefaults.standard.set(syncMessage, forKey: Self.lastHealthKitSyncMessageKey)
        }
    }
    @Published var hasHealthKitAccess: Bool

    private let healthKitService = HealthKitService()

    private static let hasHealthKitAccessKey = "hasHealthKitAccess"
    private static let lastHealthKitSyncMessageKey = "lastHealthKitSyncMessage"
    private static let defaultSyncMessage = "Health sync has not run yet."

    init() {
        let persistedAccess = UserDefaults.standard.bool(forKey: Self.hasHealthKitAccessKey)
        let persistedSyncMessage = UserDefaults.standard.string(forKey: Self.lastHealthKitSyncMessageKey)
        let liveStatus = healthKitService.hasCurrentAuthorization()

        syncMessage = persistedSyncMessage ?? Self.defaultSyncMessage
        hasHealthKitAccess = liveStatus

        if persistedAccess != liveStatus {
            UserDefaults.standard.set(liveStatus, forKey: Self.hasHealthKitAccessKey)
        }
    }

    func refreshAuthorizationStatus() {
        let liveStatus = healthKitService.hasCurrentAuthorization()
        hasHealthKitAccess = liveStatus
        UserDefaults.standard.set(liveStatus, forKey: Self.hasHealthKitAccessKey)
    }

    func requestAuthorization(includeActiveCalories: Bool) async -> Bool {
        do {
            try await healthKitService.requestAuthorization(includeActiveCalories: includeActiveCalories)
            refreshAuthorizationStatus()
            recordSyncStatus(
                includeActiveCalories
                ? "HealthKit access granted for sync and active calorie adjustments."
                : "HealthKit access granted for Health sync."
            )
            return true
        } catch {
            hasHealthKitAccess = false
            UserDefaults.standard.set(false, forKey: Self.hasHealthKitAccessKey)
            recordSyncStatus("HealthKit authorization failed: \(error.localizedDescription)")
            return false
        }
    }

    func pullLatestEntries(from startDate: Date, to endDate: Date) async -> [CalorieEntryPayload] {
        do {
            let payloads = try await healthKitService.fetchEntries(from: startDate, to: endDate)
            recordSyncStatus(
                "Last HealthKit pull: \(payloads.count) entries at \(Date.now.formatted(date: .omitted, time: .shortened))"
            )
            return payloads
        } catch {
            recordSyncStatus("HealthKit pull failed: \(error.localizedDescription)")
            return []
        }
    }

    func deleteEntriesFromHealthKit(_ entries: [CalorieEntryPayload]) async {
        do {
            try await healthKitService.deleteEntries(entries)
        } catch {
            recordSyncStatus("HealthKit delete failed: \(error.localizedDescription)")
        }
    }

    func sync(localEntries: [CalorieEntryPayload]) async -> [CalorieEntryPayload] {
        do {
            let merged = try await healthKitService.syncReadFirst(localEntries: localEntries)
            recordSyncStatus("Last HealthKit merge sync: \(Date.now.formatted(date: .omitted, time: .shortened))")
            return merged
        } catch {
            recordSyncStatus("HealthKit sync failed: \(error.localizedDescription)")
            return localEntries
        }
    }

    func updateActiveCaloriesSyncStatus(dailyCalories: Double, weeklyCalories: Double, syncedAt: Date = .now) {
        recordSyncStatus(
            "Last sync: \(syncedAt.formatted(date: .omitted, time: .shortened))"
        )
    }

    func recordSyncStatus(_ message: String) {
        syncMessage = message
    }

    func pullActiveCaloriesBurned(from startDate: Date, to endDate: Date) async -> ActiveCaloriesReadResult {
        do {
            let calories = try await healthKitService.fetchActiveCaloriesBurned(from: startDate, to: endDate)
            return ActiveCaloriesReadResult(calories: calories, fallbackNote: nil)
        } catch {
            let note = "Active calories unavailable right now. Using base targets only until Health data is available."
            recordSyncStatus("HealthKit active calories read failed: \(error.localizedDescription)")
            return ActiveCaloriesReadResult(calories: 0, fallbackNote: note)
        }
    }
}
