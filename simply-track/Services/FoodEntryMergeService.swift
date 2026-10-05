import Foundation

/// Centralizes upsert/merge rules for FoodEntry updates coming from local edits and HealthKit payloads.
enum FoodEntryMergeService {
    static func deduplicatedLatestByID(_ snapshots: [CalorieEntryPayload]) -> [CalorieEntryPayload] {
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

    static func upsert(
        _ payloads: [CalorieEntryPayload],
        into entries: [FoodEntry],
        sourceOverride: String? = nil,
        insert: (FoodEntry) -> Void
    ) {
        var entriesByID: [UUID: FoodEntry] = [:]
        var entriesBySampleID: [String: FoodEntry] = [:]

        for entry in entries {
            entriesByID[entry.id] = entry
            if let sampleID = normalizedSampleID(entry.healthKitSampleIdentifier) {
                entriesBySampleID[sampleID] = entry
            }
        }

        for payload in payloads {
            let resolvedSampleID = normalizedSampleID(payload.healthKitSampleIdentifier)
            let existing = resolvedSampleID.flatMap { entriesBySampleID[$0] } ?? entriesByID[payload.id]

            if let existing {
                apply(payload: payload, to: existing, sourceOverride: sourceOverride)
                if let updatedSampleID = normalizedSampleID(existing.healthKitSampleIdentifier) {
                    entriesBySampleID[updatedSampleID] = existing
                }
            } else {
                let newEntry = makeEntry(from: payload, sourceOverride: sourceOverride)
                insert(newEntry)
                entriesByID[newEntry.id] = newEntry
                if let newSampleID = normalizedSampleID(newEntry.healthKitSampleIdentifier) {
                    entriesBySampleID[newSampleID] = newEntry
                }
            }
        }
    }

    private static func normalizedSampleID(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func apply(payload: CalorieEntryPayload, to entry: FoodEntry, sourceOverride: String?) {
        guard payload.updatedAt >= entry.updatedAt else { return }
        entry.foodName = payload.foodName
        entry.amountDescription = payload.amountDescription
        entry.calories = payload.calories
        entry.consumedAt = payload.consumedAt
        entry.updatedAt = payload.updatedAt
        entry.healthKitSampleIdentifier = payload.healthKitSampleIdentifier
        entry.source = sourceOverride ?? payload.source
    }

    private static func makeEntry(from payload: CalorieEntryPayload, sourceOverride: String?) -> FoodEntry {
        FoodEntry(
            id: payload.id,
            foodName: payload.foodName,
            amountDescription: payload.amountDescription,
            calories: payload.calories,
            consumedAt: payload.consumedAt,
            updatedAt: payload.updatedAt,
            source: sourceOverride ?? payload.source,
            healthKitSampleIdentifier: payload.healthKitSampleIdentifier
        )
    }
}
