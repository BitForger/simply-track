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
    @Published var syncMessage = ""
    @Published var hasHealthKitAccess: Bool
    private let healthKitService = HealthKitService()

    private static let hasHealthKitAccessKey = "hasHealthKitAccess"

    init() {
        hasHealthKitAccess = UserDefaults.standard.bool(forKey: Self.hasHealthKitAccessKey)
    }

    func requestAuthorization() async {
        do {
            try await healthKitService.requestAuthorization()
            hasHealthKitAccess = true
            UserDefaults.standard.set(true, forKey: Self.hasHealthKitAccessKey)
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
