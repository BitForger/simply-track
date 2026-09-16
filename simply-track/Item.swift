//
//  Item.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation
import SwiftData

enum BiologicalSex: String, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
}

enum WeeklyAggregateStatus: String {
    case onTrack
    case aboveTarget
    case belowTarget
}

enum NutritionGoal: String, CaseIterable, Identifiable {
    case maintain
    case loseWeight

    var id: String { rawValue }

    var title: String {
        switch self {
        case .maintain: return "Maintain Weight"
        case .loseWeight: return "Lose Weight"
        }
    }
}

enum WeightLossPace: String, CaseIterable, Identifiable {
    case halfPoundPerWeek
    case onePoundPerWeek
    case oneAndHalfPoundsPerWeek
    case twoPoundsPerWeek

    var id: String { rawValue }

    var title: String {
        switch self {
        case .halfPoundPerWeek: return "Light (0.5 lb/week)"
        case .onePoundPerWeek: return "Moderate (1.0 lb/week)"
        case .oneAndHalfPoundsPerWeek: return "Strong (1.5 lb/week)"
        case .twoPoundsPerWeek: return "Aggressive (2.0 lb/week)"
        }
    }

    var dailyCalorieDeficit: Double {
        switch self {
        case .halfPoundPerWeek: return 250
        case .onePoundPerWeek: return 500
        case .oneAndHalfPoundsPerWeek: return 750
        case .twoPoundsPerWeek: return 1000
        }
    }
}

enum SimplyTrackSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FoodEntry.self, FoodCatalogItem.self, UserProfile.self]
    }

    @Model
    final class FoodEntry {
        @Attribute(.unique) var id: UUID
        var foodName: String
        var amountDescription: String
        var calories: Double
        var consumedAt: Date
        var updatedAt: Date
        var source: String
        var healthKitSampleIdentifier: String?

        init(
            id: UUID = UUID(),
            foodName: String,
            amountDescription: String,
            calories: Double,
            consumedAt: Date = .now,
            updatedAt: Date = .now,
            source: String = "manual",
            healthKitSampleIdentifier: String? = nil
        ) {
            self.id = id
            self.foodName = foodName
            self.amountDescription = amountDescription
            self.calories = calories
            self.consumedAt = consumedAt
            self.updatedAt = updatedAt
            self.source = source
            self.healthKitSampleIdentifier = healthKitSampleIdentifier
        }
    }

    @Model
    final class FoodCatalogItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var defaultAmountDescription: String
        var caloriesPerDefaultAmount: Double

        init(
            id: UUID = UUID(),
            name: String,
            defaultAmountDescription: String,
            caloriesPerDefaultAmount: Double
        ) {
            self.id = id
            self.name = name
            self.defaultAmountDescription = defaultAmountDescription
            self.caloriesPerDefaultAmount = caloriesPerDefaultAmount
        }
    }

    @Model
    final class UserProfile {
        @Attribute(.unique) var id: UUID
        var age: Int
        var sexRawValue: String
        var heightCm: Double
        var weightKg: Double
        var activityMultiplier: Double
        var dailyCalorieTarget: Double
        var weeklyCalorieTarget: Double
        var selectedTargetModeRawValue: String
        var nutritionGoalRawValue: String
        var weightLossPaceRawValue: String

        init(
            id: UUID = UUID(),
            age: Int = 30,
            sexRawValue: String = BiologicalSex.male.rawValue,
            heightCm: Double = 175,
            weightKg: Double = 75,
            activityMultiplier: Double = 1.375,
            dailyCalorieTarget: Double? = nil,
            weeklyCalorieTarget: Double? = nil,
            selectedTargetModeRawValue: String = "weekly",
            nutritionGoalRawValue: String = NutritionGoal.maintain.rawValue,
            weightLossPaceRawValue: String = WeightLossPace.onePoundPerWeek.rawValue
        ) {
            self.id = id
            self.age = age
            self.sexRawValue = sexRawValue
            self.heightCm = heightCm
            self.weightKg = weightKg
            self.activityMultiplier = activityMultiplier
            self.dailyCalorieTarget = 0
            self.weeklyCalorieTarget = 0
            self.selectedTargetModeRawValue = selectedTargetModeRawValue
            self.nutritionGoalRawValue = nutritionGoalRawValue
            self.weightLossPaceRawValue = weightLossPaceRawValue

            let defaultDailyTarget = estimatedTDEE()
            self.dailyCalorieTarget = dailyCalorieTarget ?? defaultDailyTarget
            self.weeklyCalorieTarget = weeklyCalorieTarget ?? (defaultDailyTarget * 7)
        }

        var biologicalSex: BiologicalSex {
            get { BiologicalSex(rawValue: sexRawValue) ?? .male }
            set { sexRawValue = newValue.rawValue }
        }

        var nutritionGoal: NutritionGoal {
            get { NutritionGoal(rawValue: nutritionGoalRawValue) ?? .maintain }
            set { nutritionGoalRawValue = newValue.rawValue }
        }

        var weightLossPace: WeightLossPace {
            get { WeightLossPace(rawValue: weightLossPaceRawValue) ?? .onePoundPerWeek }
            set { weightLossPaceRawValue = newValue.rawValue }
        }

        func estimatedBMR() -> Double {
            let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
            return biologicalSex == .male ? base + 5 : base - 161
        }

        func estimatedTDEE() -> Double {
            estimatedBMR() * activityMultiplier
        }

        func recommendedDailyTarget() -> Double {
            let base = estimatedTDEE()
            guard nutritionGoal == .loseWeight else { return base }
            return max(1200, base - weightLossPace.dailyCalorieDeficit)
        }

        func recommendedWeeklyTarget() -> Double {
            recommendedDailyTarget() * 7
        }
    }
}

enum SimplyTrackSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FoodEntry.self, FoodCatalogItem.self, UserProfile.self]
    }

    @Model
    final class FoodEntry {
        @Attribute(.unique) var id: UUID
        var foodName: String
        var amountDescription: String
        var calories: Double
        var consumedAt: Date
        var updatedAt: Date
        var source: String
        var healthKitSampleIdentifier: String?

        init(
            id: UUID = UUID(),
            foodName: String,
            amountDescription: String,
            calories: Double,
            consumedAt: Date = .now,
            updatedAt: Date = .now,
            source: String = "manual",
            healthKitSampleIdentifier: String? = nil
        ) {
            self.id = id
            self.foodName = foodName
            self.amountDescription = amountDescription
            self.calories = calories
            self.consumedAt = consumedAt
            self.updatedAt = updatedAt
            self.source = source
            self.healthKitSampleIdentifier = healthKitSampleIdentifier
        }
    }

    @Model
    final class FoodCatalogItem {
        @Attribute(.unique) var id: UUID
        var name: String
        var defaultAmountDescription: String
        var caloriesPerDefaultAmount: Double

        init(
            id: UUID = UUID(),
            name: String,
            defaultAmountDescription: String,
            caloriesPerDefaultAmount: Double
        ) {
            self.id = id
            self.name = name
            self.defaultAmountDescription = defaultAmountDescription
            self.caloriesPerDefaultAmount = caloriesPerDefaultAmount
        }
    }

    @Model
    final class UserProfile {
        @Attribute(.unique) var id: UUID
        var age: Int
        var sexRawValue: String
        var heightCm: Double
        var weightKg: Double
        var activityMultiplier: Double
        var dailyCalorieTarget: Double
        var weeklyCalorieTarget: Double
        var nutritionGoalRawValue: String
        var weightLossPaceRawValue: String

        init(
            id: UUID = UUID(),
            age: Int = 30,
            sexRawValue: String = BiologicalSex.male.rawValue,
            heightCm: Double = 175,
            weightKg: Double = 75,
            activityMultiplier: Double = 1.375,
            dailyCalorieTarget: Double? = nil,
            weeklyCalorieTarget: Double? = nil,
            nutritionGoalRawValue: String = NutritionGoal.maintain.rawValue,
            weightLossPaceRawValue: String = WeightLossPace.onePoundPerWeek.rawValue
        ) {
            self.id = id
            self.age = age
            self.sexRawValue = sexRawValue
            self.heightCm = heightCm
            self.weightKg = weightKg
            self.activityMultiplier = activityMultiplier
            self.dailyCalorieTarget = 0
            self.weeklyCalorieTarget = 0
            self.nutritionGoalRawValue = nutritionGoalRawValue
            self.weightLossPaceRawValue = weightLossPaceRawValue

            let defaultDailyTarget = estimatedTDEE()
            self.dailyCalorieTarget = dailyCalorieTarget ?? defaultDailyTarget
            self.weeklyCalorieTarget = weeklyCalorieTarget ?? (defaultDailyTarget * 7)
        }

        var biologicalSex: BiologicalSex {
            get { BiologicalSex(rawValue: sexRawValue) ?? .male }
            set { sexRawValue = newValue.rawValue }
        }

        var nutritionGoal: NutritionGoal {
            get { NutritionGoal(rawValue: nutritionGoalRawValue) ?? .maintain }
            set { nutritionGoalRawValue = newValue.rawValue }
        }

        var weightLossPace: WeightLossPace {
            get { WeightLossPace(rawValue: weightLossPaceRawValue) ?? .onePoundPerWeek }
            set { weightLossPaceRawValue = newValue.rawValue }
        }

        func estimatedBMR() -> Double {
            let base = 10 * weightKg + 6.25 * heightCm - 5 * Double(age)
            return biologicalSex == .male ? base + 5 : base - 161
        }

        func estimatedTDEE() -> Double {
            estimatedBMR() * activityMultiplier
        }

        func recommendedDailyTarget() -> Double {
            let base = estimatedTDEE()
            guard nutritionGoal == .loseWeight else { return base }
            return max(1200, base - weightLossPace.dailyCalorieDeficit)
        }

        func recommendedWeeklyTarget() -> Double {
            recommendedDailyTarget() * 7
        }
    }
}

enum SimplyTrackMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SimplyTrackSchemaV1.self, SimplyTrackSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: SimplyTrackSchemaV1.self,
        toVersion: SimplyTrackSchemaV2.self
    )
}

typealias FoodEntry = SimplyTrackSchemaV2.FoodEntry
typealias FoodCatalogItem = SimplyTrackSchemaV2.FoodCatalogItem
typealias UserProfile = SimplyTrackSchemaV2.UserProfile

struct FoodCatalogSeed {
    static let defaults: [(name: String, amount: String, calories: Double)] = [
        ("Banana", "1 medium", 105),
        ("Chicken Breast", "100 g", 165),
        ("Cooked Rice", "1 cup", 206),
        ("Egg", "1 large", 72),
        ("Greek Yogurt", "170 g", 100),
        ("Oatmeal", "1 cup cooked", 154),
        ("Peanut Butter", "1 tbsp", 94),
        ("Salmon", "100 g", 208),
        ("Whole Milk", "1 cup", 149),
        ("Whole Wheat Bread", "1 slice", 81)
    ]
}

struct CalorieSummaryCalculator {
    static func dailyTotal(from entries: [FoodEntry], on day: Date, calendar: Calendar = .current) -> Double {
        entries
            .filter { calendar.isDate($0.consumedAt, inSameDayAs: day) }
            .reduce(0) { $0 + $1.calories }
    }

    static func weekRange(for date: Date, calendar: Calendar = .gregorianSundayStart) -> DateInterval {
        let start = calendar.startOfWeekSunday(for: date)
        let end = calendar.date(byAdding: .day, value: 7, to: start) ?? date
        return DateInterval(start: start, end: end)
    }

    static func weeklyTotal(from entries: [FoodEntry], around date: Date, calendar: Calendar = .gregorianSundayStart) -> Double {
        let range = weekRange(for: date, calendar: calendar)
        return entries
            .filter { range.contains($0.consumedAt) }
            .reduce(0) { $0 + $1.calories }
    }

    static func weeklyStatus(total: Double, target: Double, tolerance: Double = 0.05) -> WeeklyAggregateStatus {
        if target <= 0 { return .onTrack }
        let ratio = total / target
        if ratio > (1 + tolerance) { return .aboveTarget }
        if ratio < (1 - tolerance) { return .belowTarget }
        return .onTrack
    }

    static func weeklyProgress(total: Double, target: Double) -> Double {
        guard target > 0 else { return 0 }
        return total / target
    }

    static func remainingWeeklyCalories(total: Double, target: Double) -> Double {
        max(0, target - total)
    }
}

struct StreakCalculator {
    static func currentDailyLoggingStreak(entries: [FoodEntry], calendar: Calendar = .gregorianSundayStart) -> Int {
        let loggedDays = Set(entries.map { calendar.startOfDay(for: $0.consumedAt) })
        guard !loggedDays.isEmpty else { return 0 }

        var streak = 0
        var dayCursor = calendar.startOfDay(for: .now)

        while loggedDays.contains(dayCursor) {
            streak += 1
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: dayCursor) else { break }
            dayCursor = previousDay
        }

        return streak
    }

    static func weekLoggedDays(entries: [FoodEntry], around date: Date, calendar: Calendar = .gregorianSundayStart) -> Int {
        let range = CalorieSummaryCalculator.weekRange(for: date, calendar: calendar)
        let loggedDays = Set(
            entries
                .filter { range.contains($0.consumedAt) }
                .map { calendar.startOfDay(for: $0.consumedAt) }
        )
        return loggedDays.count
    }
}

extension Calendar {
    static var gregorianSundayStart: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }

    func startOfWeekSunday(for date: Date) -> Date {
        let dayStart = startOfDay(for: date)
        let weekday = component(.weekday, from: dayStart)
        let daysFromSunday = (weekday - firstWeekday + 7) % 7
        return self.date(byAdding: .day, value: -daysFromSunday, to: dayStart) ?? dayStart
    }
}
