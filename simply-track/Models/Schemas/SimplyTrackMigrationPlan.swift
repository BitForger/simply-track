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
        [SimplyTrackSchemaV1.self, SimplyTrackSchemaV2.self, SimplyTrackSchemaV3.self, SimplyTrackSchemaV4.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
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
}

typealias FoodEntry = SimplyTrackSchemaV4.FoodEntry
typealias FoodCatalogItem = SimplyTrackSchemaV4.FoodCatalogItem
typealias UserProfile = SimplyTrackSchemaV4.UserProfile
