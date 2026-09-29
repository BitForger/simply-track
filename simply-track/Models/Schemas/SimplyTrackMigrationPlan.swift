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
        [SimplyTrackSchemaV1.self, SimplyTrackSchemaV2.self, SimplyTrackSchemaV3.self, SimplyTrackSchemaV4.self, SimplyTrackSchemaV5.self, SimplyTrackSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
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
}

typealias FoodEntry = SimplyTrackSchemaV6.FoodEntry
typealias FoodCatalogItem = SimplyTrackSchemaV6.FoodCatalogItem
typealias UserProfile = SimplyTrackSchemaV6.UserProfile
