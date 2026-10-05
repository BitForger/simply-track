import Foundation

struct HealthImportCandidateRecord: Hashable {
    let name: String
    let amountDescription: String
    let calories: Double
}

enum HealthImportCandidateService {
    static func shouldUseCachedResult(fetchedAt: Date?, ttl: TimeInterval, now: Date = .now) -> Bool {
        guard let fetchedAt else { return false }
        return now.timeIntervalSince(fetchedAt) <= ttl
    }

    static func makeFetchWindows(
        from startDate: Date,
        to endDate: Date,
        stepDays: Int,
        calendar: Calendar = .current
    ) -> [(start: Date, end: Date)] {
        guard startDate < endDate, stepDays > 0 else {
            return [(start: startDate, end: endDate)]
        }

        var windows: [(start: Date, end: Date)] = []
        var cursor = startDate

        while cursor < endDate {
            let next = min(calendar.date(byAdding: .day, value: stepDays, to: cursor) ?? endDate, endDate)
            windows.append((start: cursor, end: next))
            cursor = next
        }

        return windows
    }

    static func localFallbackCandidates(
        from entries: [FoodEntry],
        existingCatalog: [FoodCatalogItem]
    ) -> [HealthImportCandidateRecord] {
        let healthKitEntries = entries.filter { $0.source == "healthKit" }
        var latestByName: [String: FoodEntry] = [:]

        for entry in healthKitEntries {
            let key = normalizedKey(entry.foodName)
            guard !key.isEmpty else { continue }
            if let existing = latestByName[key], existing.consumedAt >= entry.consumedAt {
                continue
            }
            latestByName[key] = entry
        }

        return latestByName.values
            .filter { entry in !containsCatalogItem(named: entry.foodName, in: existingCatalog) }
            .map {
                HealthImportCandidateRecord(
                    name: $0.foodName,
                    amountDescription: $0.amountDescription,
                    calories: $0.calories
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static func importedCandidates(
        from payloads: [CalorieEntryPayload],
        existingCatalog: [FoodCatalogItem]
    ) -> [HealthImportCandidateRecord] {
        var latestByName: [String: CalorieEntryPayload] = [:]

        for payload in payloads {
            let key = normalizedKey(payload.foodName)
            guard !key.isEmpty else { continue }
            if let existing = latestByName[key], existing.consumedAt >= payload.consumedAt {
                continue
            }
            latestByName[key] = payload
        }

        return latestByName.values
            .filter { payload in !containsCatalogItem(named: payload.foodName, in: existingCatalog) }
            .map {
                HealthImportCandidateRecord(
                    name: $0.foodName,
                    amountDescription: $0.amountDescription,
                    calories: $0.calories
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func containsCatalogItem(named name: String, in catalog: [FoodCatalogItem]) -> Bool {
        let key = normalizedKey(name)
        return catalog.contains { normalizedKey($0.name) == key }
    }

    private static func normalizedKey(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
