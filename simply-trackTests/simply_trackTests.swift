//
//  simply_trackTests.swift
//  simply-trackTests
//
//  Created by Noah on 10/3/26.
//

import XCTest
import SwiftData
@testable import simply_track

final class simply_trackTests: XCTestCase {
    private func makeV6Context() throws -> ModelContext {
        let schema = Schema(SimplyTrackSchemaV6.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    func testV6DeduplicationKeepsNewestFoodEntryPerID() throws {
        let context = try makeV6Context()
        let sharedID = UUID()

        let older = SimplyTrackSchemaV6.FoodEntry(
            id: sharedID,
            foodName: "Older",
            amountDescription: "1 serving",
            calories: 200,
            consumedAt: .now.addingTimeInterval(-600),
            updatedAt: .now.addingTimeInterval(-300),
            source: "manual"
        )

        let newer = SimplyTrackSchemaV6.FoodEntry(
            id: sharedID,
            foodName: "Newer",
            amountDescription: "2 servings",
            calories: 450,
            consumedAt: .now,
            updatedAt: .now,
            source: "manual"
        )

        context.insert(older)
        context.insert(newer)
        try context.save()

        try SimplyTrackMigrationPlan.performV6Deduplication(in: context)

        let results = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodEntry>())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].foodName, "Newer")
        XCTAssertEqual(results[0].calories, 450)
    }

    func testV6DeduplicationPrefersUserAddedCatalogItemForDuplicateID() throws {
        let context = try makeV6Context()
        let sharedID = UUID()

        let seeded = SimplyTrackSchemaV6.FoodCatalogItem(
            id: sharedID,
            name: "Chicken Breast",
            defaultAmountDescription: "100 g",
            caloriesPerDefaultAmount: 165,
            isUserAdded: false
        )

        let userAdded = SimplyTrackSchemaV6.FoodCatalogItem(
            id: sharedID,
            name: "My Chicken",
            defaultAmountDescription: "120 g",
            caloriesPerDefaultAmount: 200,
            isUserAdded: true
        )

        context.insert(seeded)
        context.insert(userAdded)
        try context.save()

        try SimplyTrackMigrationPlan.performV6Deduplication(in: context)

        let results = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodCatalogItem>())
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].name, "My Chicken")
        XCTAssertTrue(results[0].isUserAdded)
    }

    func testV6DeduplicationKeepsHigherScoredUserProfileForDuplicateID() throws {
        let context = try makeV6Context()
        let sharedID = UUID()

        let lowerScore = SimplyTrackSchemaV6.UserProfile(
            id: sharedID,
            dailyCalorieTarget: 0,
            weeklyCalorieTarget: 0,
            hasCompletedQuickStart: false,
            useHealthSync: false,
            enableReminders: false
        )

        let higherScore = SimplyTrackSchemaV6.UserProfile(
            id: sharedID,
            dailyCalorieTarget: 2200,
            weeklyCalorieTarget: 15400,
            hasCompletedQuickStart: true,
            useHealthSync: true,
            enableReminders: true
        )

        context.insert(lowerScore)
        context.insert(higherScore)
        try context.save()

        try SimplyTrackMigrationPlan.performV6Deduplication(in: context)

        let results = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.UserProfile>())
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].hasCompletedQuickStart)
        XCTAssertTrue(results[0].useHealthSync)
        XCTAssertTrue(results[0].enableReminders)
        XCTAssertEqual(results[0].dailyCalorieTarget, 2200)
        XCTAssertEqual(results[0].weeklyCalorieTarget, 15400)
    }
}
