//
//  HealthKitService.swift
//  simply-track
//
//  Created by Noah on 10/2/26.
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

final class HealthKitService {
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

    func hasCurrentAuthorization() -> Bool {
#if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return false
        }

        return store.authorizationStatus(for: dietaryType) == .sharingAuthorized
#else
        return false
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
