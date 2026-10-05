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

    func testV6DeduplicationKeepsNewestFoodEntryPerID() {
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

        let winner = preferredFoodEntry([older, newer])
        XCTAssertEqual(winner.foodName, "Newer")
        XCTAssertEqual(winner.calories, 450)
    }

    func testV6DeduplicationPrefersUserAddedCatalogItemForDuplicateID() {
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

        let winner = preferredFoodCatalogItem([seeded, userAdded])
        XCTAssertEqual(winner.name, "My Chicken")
        XCTAssertTrue(winner.isUserAdded)
    }

    func testV6DeduplicationKeepsHigherScoredUserProfileForDuplicateID() {
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

        let winner = preferredUserProfile([lowerScore, higherScore])
        XCTAssertTrue(winner.hasCompletedQuickStart)
        XCTAssertTrue(winner.useHealthSync)
        XCTAssertTrue(winner.enableReminders)
        XCTAssertEqual(winner.dailyCalorieTarget, 2200)
        XCTAssertEqual(winner.weeklyCalorieTarget, 15400)
    }

    func testWeekRangeStartsOnSundayAndExcludesFollowingSunday() {
        let wednesday = makeUTCDate(year: 2026, month: 10, day: 7, hour: 12)
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        utcCalendar.firstWeekday = 1

        let expectedStart = utcCalendar.startOfWeekSunday(for: wednesday)
        let expectedEnd = utcCalendar.date(byAdding: .day, value: 7, to: expectedStart)!
        let range = CalorieSummaryCalculator.weekRange(for: wednesday, calendar: utcCalendar)

        XCTAssertEqual(range.start, expectedStart)
        XCTAssertEqual(range.end, expectedEnd)
        XCTAssertTrue(range.contains(expectedEnd.addingTimeInterval(-60)))
        XCTAssertFalse(range.contains(expectedEnd.addingTimeInterval(60)))
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

    private func preferredFoodEntry(_ entries: [SimplyTrackSchemaV6.FoodEntry]) -> SimplyTrackSchemaV6.FoodEntry {
        entries.max { lhs, rhs in
            if lhs.updatedAt != rhs.updatedAt { return lhs.updatedAt < rhs.updatedAt }
            if lhs.consumedAt != rhs.consumedAt { return lhs.consumedAt < rhs.consumedAt }
            return lhs.calories < rhs.calories
        }!
    }

    private func preferredFoodCatalogItem(_ items: [SimplyTrackSchemaV6.FoodCatalogItem]) -> SimplyTrackSchemaV6.FoodCatalogItem {
        items.max { lhs, rhs in
            if lhs.isUserAdded != rhs.isUserAdded { return rhs.isUserAdded }
            if lhs.name != rhs.name { return lhs.name > rhs.name }
            return lhs.caloriesPerDefaultAmount < rhs.caloriesPerDefaultAmount
        }!
    }

    private func preferredUserProfile(_ profiles: [SimplyTrackSchemaV6.UserProfile]) -> SimplyTrackSchemaV6.UserProfile {
        profiles.max { lhs, rhs in
            userProfileScore(lhs) < userProfileScore(rhs)
        }!
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
