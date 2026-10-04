//
//  SimplyTrackMigrationPlan.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation
import SwiftData

enum SimplyTrackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SimplyTrackSchemaV1.self, SimplyTrackSchemaV2.self, SimplyTrackSchemaV3.self, SimplyTrackSchemaV4.self, SimplyTrackSchemaV5.self, SimplyTrackSchemaV6.self, SimplyTrackSchemaV7.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6, migrateV6toV7]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV1.self,
        toVersion: SimplyTrackSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV2.self,
        toVersion: SimplyTrackSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV3.self,
        toVersion: SimplyTrackSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV4.self,
        toVersion: SimplyTrackSchemaV5.self
    )

    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV5.self,
        toVersion: SimplyTrackSchemaV6.self
    )

    static let migrateV6toV7 = MigrationStage.custom(
        fromVersion: SimplyTrackSchemaV6.self,
        toVersion: SimplyTrackSchemaV7.self,
        willMigrate: { context in
            try performV6Deduplication(in: context)
        },
        didMigrate: nil
    )

    static func performV6Deduplication(in context: ModelContext) throws {
        try deduplicateFoodEntries(in: context)
        try deduplicateFoodCatalogItems(in: context)
        try deduplicateUserProfiles(in: context)
        try context.save()
    }

    static func deduplicateFoodEntries(in context: ModelContext) throws {
        var latestByID: [UUID: SimplyTrackSchemaV6.FoodEntry] = [:]
        let entries = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodEntry>())

        for entry in entries {
            if let existing = latestByID[entry.id] {
                if entry.updatedAt >= existing.updatedAt {
                    context.delete(existing)
                    latestByID[entry.id] = entry
                } else {
                    context.delete(entry)
                }
            } else {
                latestByID[entry.id] = entry
            }
        }
    }

    static func deduplicateFoodCatalogItems(in context: ModelContext) throws {
        var keepByID: [UUID: SimplyTrackSchemaV6.FoodCatalogItem] = [:]
        let items = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodCatalogItem>())

        for item in items {
            if let existing = keepByID[item.id] {
                // Prefer user-added entries over seeded entries when IDs collide.
                if item.isUserAdded && !existing.isUserAdded {
                    context.delete(existing)
                    keepByID[item.id] = item
                } else {
                    context.delete(item)
                }
            } else {
                keepByID[item.id] = item
            }
        }
    }

    static func deduplicateUserProfiles(in context: ModelContext) throws {
        var keepByID: [UUID: SimplyTrackSchemaV6.UserProfile] = [:]
        let profiles = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.UserProfile>())

        for profile in profiles {
            if let existing = keepByID[profile.id] {
                let existingScore = score(profile: existing)
                let incomingScore = score(profile: profile)
                if incomingScore >= existingScore {
                    context.delete(existing)
                    keepByID[profile.id] = profile
                } else {
                    context.delete(profile)
                }
            } else {
                keepByID[profile.id] = profile
            }
        }
    }

    static func score(profile: SimplyTrackSchemaV6.UserProfile) -> Int {
        var score = 0
        if profile.hasCompletedQuickStart { score += 10 }
        if profile.useHealthSync { score += 2 }
        if profile.enableReminders { score += 1 }
        if profile.dailyCalorieTarget > 0 { score += 1 }
        if profile.weeklyCalorieTarget > 0 { score += 1 }
        return score
    }
}

typealias FoodEntry = SimplyTrackSchemaV7.FoodEntry
typealias FoodCatalogItem = SimplyTrackSchemaV7.FoodCatalogItem
typealias UserProfile = SimplyTrackSchemaV7.UserProfile
