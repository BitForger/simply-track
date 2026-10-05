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
    private let lastHealthKitSyncMessageKey = "lastHealthKitSyncMessage"
    private let hasHealthKitAccessKey = "hasHealthKitAccess"

    private func makeV6Context() throws -> ModelContext {
        let schema = Schema(SimplyTrackSchemaV6.models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        return ModelContext(container)
    }

    private func makeUTCDate(year: Int, month: Int, day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return components.date!
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

        try deduplicateV6Records(in: context)

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

        try deduplicateV6Records(in: context)

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

        try deduplicateV6Records(in: context)

        let results = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.UserProfile>())
        XCTAssertEqual(results.count, 1)
        XCTAssertTrue(results[0].hasCompletedQuickStart)
        XCTAssertTrue(results[0].useHealthSync)
        XCTAssertTrue(results[0].enableReminders)
        XCTAssertEqual(results[0].dailyCalorieTarget, 2200)
        XCTAssertEqual(results[0].weeklyCalorieTarget, 15400)
    }

    func testWeekRangeStartsOnSundayAndExcludesFollowingSunday() {
        let wednesday = makeUTCDate(year: 2026, month: 10, day: 7, hour: 12)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        utcCalendar.firstWeekday = 1
        let range = CalorieSummaryCalculator.weekRange(for: wednesday, calendar: utcCalendar)

        XCTAssertEqual(range.start, makeUTCDate(year: 2026, month: 10, day: 4, hour: 0))
        XCTAssertEqual(range.end, makeUTCDate(year: 2026, month: 10, day: 11, hour: 0))
        XCTAssertTrue(range.contains(makeUTCDate(year: 2026, month: 10, day: 10, hour: 23, minute: 59)))
        XCTAssertFalse(range.contains(makeUTCDate(year: 2026, month: 10, day: 11, hour: 0, minute: 0)))
    }

    func testDailyAndWeeklyTotalsUseExpectedBoundaries() {
        let sunday = makeUTCDate(year: 2026, month: 10, day: 4, hour: 9)
        let wednesday = makeUTCDate(year: 2026, month: 10, day: 7, hour: 12)
        let saturday = makeUTCDate(year: 2026, month: 10, day: 10, hour: 23, minute: 30)
        let previousSaturday = makeUTCDate(year: 2026, month: 10, day: 3, hour: 20)

        let entries = [
            SimplyTrackSchemaV7.FoodEntry(foodName: "Sunday", amountDescription: "1 serving", calories: 100, consumedAt: sunday),
            SimplyTrackSchemaV7.FoodEntry(foodName: "Wednesday", amountDescription: "1 serving", calories: 250, consumedAt: wednesday),
            SimplyTrackSchemaV7.FoodEntry(foodName: "Saturday", amountDescription: "1 serving", calories: 400, consumedAt: saturday),
            SimplyTrackSchemaV7.FoodEntry(foodName: "Previous Saturday", amountDescription: "1 serving", calories: 900, consumedAt: previousSaturday)
        ]

        XCTAssertEqual(CalorieSummaryCalculator.dailyTotal(from: entries, on: wednesday), 250)
        XCTAssertEqual(CalorieSummaryCalculator.weeklyTotal(from: entries, around: wednesday), 750)
    }

    func testWeeklyStatusAndRemainingCaloriesAreConsistent() {
        XCTAssertEqual(CalorieSummaryCalculator.weeklyStatus(total: 2100, target: 2000), .onTrack)
        XCTAssertEqual(CalorieSummaryCalculator.weeklyStatus(total: 2201, target: 2000), .aboveTarget)
        XCTAssertEqual(CalorieSummaryCalculator.weeklyStatus(total: 1800, target: 2000), .belowTarget)
        XCTAssertEqual(CalorieSummaryCalculator.weeklyProgress(total: 1500, target: 2000), 0.75, accuracy: 0.001)
        XCTAssertEqual(CalorieSummaryCalculator.weeklyProgress(total: 1500, target: 0), 0)
        XCTAssertEqual(CalorieSummaryCalculator.remainingWeeklyCalories(total: 2201, target: 2000), 0)
        XCTAssertEqual(CalorieSummaryCalculator.remainingWeeklyCalories(total: 1500, target: 2000), 500)
    }

    func testUserProfileUsesMifflinStJeorForDefaultTargets() {
        let profile = SimplyTrackSchemaV7.UserProfile()

        XCTAssertEqual(profile.estimatedBMR(), 1698.75, accuracy: 0.001)
        XCTAssertEqual(profile.estimatedTDEE(), 2335.78125, accuracy: 0.001)
        XCTAssertEqual(profile.recommendedDailyTarget(), 2335.78125, accuracy: 0.001)
        XCTAssertEqual(profile.recommendedWeeklyTarget(), 16350.46875, accuracy: 0.001)
    }

    func testUserProfileUsesOtherEquationPathsAndWeightLossFloor() {
        let harrisBenedict = SimplyTrackSchemaV7.UserProfile(
            sexRawValue: BiologicalSex.female.rawValue,
            tdeeEquationRawValue: TDEEEquation.harrisBenedict.rawValue
        )
        XCTAssertEqual(harrisBenedict.estimatedBMR(), 1553.368, accuracy: 0.001)
        XCTAssertEqual(harrisBenedict.estimatedTDEE(), 2135.881, accuracy: 0.001)

        let katchFallback = SimplyTrackSchemaV7.UserProfile(
            tdeeEquationRawValue: TDEEEquation.katchMcArdle.rawValue,
            leanBodyMassKg: nil
        )
        XCTAssertEqual(katchFallback.estimatedBMR(), 1698.75, accuracy: 0.001)

        let katchWithLeanBodyMass = SimplyTrackSchemaV7.UserProfile(
            tdeeEquationRawValue: TDEEEquation.katchMcArdle.rawValue,
            leanBodyMassKg: 60
        )
        XCTAssertEqual(katchWithLeanBodyMass.estimatedBMR(), 1666, accuracy: 0.001)
        XCTAssertEqual(katchWithLeanBodyMass.estimatedTDEE(), 2290.75, accuracy: 0.001)

        let aggressiveCut = SimplyTrackSchemaV7.UserProfile(
            heightCm: 155,
            weightKg: 45,
            activityMultiplier: 1.2,
            nutritionGoalRawValue: NutritionGoal.loseWeight.rawValue,
            weightLossPaceRawValue: WeightLossPace.twoPoundsPerWeek.rawValue
        )
        XCTAssertEqual(aggressiveCut.recommendedDailyTarget(), 1200, accuracy: 0.001)
    }

    @MainActor
    func testHealthKitSyncCoordinatorUsesDefaultStatusWhenNothingPersisted() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastHealthKitSyncMessageKey)
        defaults.removeObject(forKey: hasHealthKitAccessKey)
        defer {
            defaults.removeObject(forKey: lastHealthKitSyncMessageKey)
            defaults.removeObject(forKey: hasHealthKitAccessKey)
        }

        let coordinator = HealthKitSyncCoordinator()

        XCTAssertEqual(coordinator.syncMessage, "Health sync has not run yet.")
    }

    @MainActor
    func testHealthKitSyncCoordinatorPersistsLastKnownSyncStatus() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: lastHealthKitSyncMessageKey)
        defaults.removeObject(forKey: hasHealthKitAccessKey)
        defer {
            defaults.removeObject(forKey: lastHealthKitSyncMessageKey)
            defaults.removeObject(forKey: hasHealthKitAccessKey)
        }

        let expectedMessage = "Last active-calorie sync: 210 today, 900 this week at 9:41 AM"

        let firstCoordinator = HealthKitSyncCoordinator()
        firstCoordinator.recordSyncStatus(expectedMessage)

        let reloadedCoordinator = HealthKitSyncCoordinator()
        XCTAssertEqual(reloadedCoordinator.syncMessage, expectedMessage)
    }

    private func deduplicateV6Records(in context: ModelContext) throws {
        try deduplicateFoodEntries(in: context)
        try deduplicateFoodCatalogItems(in: context)
        try deduplicateUserProfiles(in: context)
        try context.save()
    }

    private func deduplicateFoodEntries(in context: ModelContext) throws {
        let entries = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodEntry>())
        let grouped = Dictionary(grouping: entries, by: \.id)

        for duplicates in grouped.values where duplicates.count > 1 {
            let winner = duplicates.max { lhs, rhs in
                if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
                if lhs.consumedAt != rhs.consumedAt { return lhs.consumedAt < rhs.consumedAt }
                return lhs.calories < rhs.calories
            }

            for entry in duplicates where entry !== winner {
                context.delete(entry)
            }
        }
    }

    private func deduplicateFoodCatalogItems(in context: ModelContext) throws {
        let items = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.FoodCatalogItem>())
        let grouped = Dictionary(grouping: items, by: \.id)

        for duplicates in grouped.values where duplicates.count > 1 {
            let winner = duplicates.max { lhs, rhs in
                if lhs.isUserAdded != rhs.isUserAdded { return rhs.isUserAdded }
                if lhs.name != rhs.name { return lhs.name > rhs.name }
                return lhs.caloriesPerDefaultAmount < rhs.caloriesPerDefaultAmount
            }

            for item in duplicates where item !== winner {
                context.delete(item)
            }
        }
    }

    private func deduplicateUserProfiles(in context: ModelContext) throws {
        let profiles = try context.fetch(FetchDescriptor<SimplyTrackSchemaV6.UserProfile>())
        let grouped = Dictionary(grouping: profiles, by: \.id)

        for duplicates in grouped.values where duplicates.count > 1 {
            let winner = duplicates.max { lhs, rhs in
                userProfileScore(lhs) < userProfileScore(rhs)
            }

            for profile in duplicates where profile !== winner {
                context.delete(profile)
            }
        }
    }

    private func userProfileScore(_ profile: SimplyTrackSchemaV6.UserProfile) -> Double {
        var score = profile.dailyCalorieTarget + (profile.weeklyCalorieTarget / 7)
        if profile.hasCompletedQuickStart { score += 10_000 }
        if profile.useHealthSync { score += 1_000 }
        if profile.enableReminders { score += 100 }
        if profile.includeActiveCaloriesInMax { score += 10 }
        if profile.autoSaveToCatalog { score += 1 }
        return score
    }
}
