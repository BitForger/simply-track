//
//  SimplyTrackSchemaV2.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation
import SwiftData

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
