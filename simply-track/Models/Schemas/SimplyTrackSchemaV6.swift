//
//  SimplyTrackSchemaV6.swift
//  simply-track
//
//  Created by Noah on 9/28/26.
//

import Foundation
import SwiftData

enum SimplyTrackSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [FoodEntry.self, FoodCatalogItem.self, UserProfile.self]
    }

    @Model
    final class FoodEntry {
        var id: UUID = UUID()
        var foodName: String = ""
        var amountDescription: String = ""
        var calories: Double = 0
        var consumedAt: Date = Foundation.Date.distantPast
        var updatedAt: Date = Foundation.Date.distantPast
        var source: String = "manual"
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
        var id: UUID = UUID()
        var name: String = ""
        var defaultAmountDescription: String = ""
        var caloriesPerDefaultAmount: Double = 0
        var isUserAdded: Bool = false

        init(
            id: UUID = UUID(),
            name: String,
            defaultAmountDescription: String,
            caloriesPerDefaultAmount: Double,
            isUserAdded: Bool = false
        ) {
            self.id = id
            self.name = name
            self.defaultAmountDescription = defaultAmountDescription
            self.caloriesPerDefaultAmount = caloriesPerDefaultAmount
            self.isUserAdded = isUserAdded
        }
    }

    @Model
    final class UserProfile {
        var id: UUID = UUID()
        var age: Int = 30
        var sexRawValue: String = BiologicalSex.male.rawValue
        var heightCm: Double = 175
        var weightKg: Double = 75
        var activityMultiplier: Double = 1.375
        var dailyCalorieTarget: Double = 0
        var weeklyCalorieTarget: Double = 0
        var nutritionGoalRawValue: String = NutritionGoal.maintain.rawValue
        var weightLossPaceRawValue: String = WeightLossPace.onePoundPerWeek.rawValue
        var tdeeEquationRawValue: String?
        var leanBodyMassKg: Double?
        var hasCompletedQuickStart: Bool = false
        var useHealthSync: Bool = true
        var enableReminders: Bool = false
        var includeActiveCaloriesInMax: Bool = false
        var autoSaveToCatalog: Bool = true

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
            weightLossPaceRawValue: String = WeightLossPace.onePoundPerWeek.rawValue,
            tdeeEquationRawValue: String? = TDEEEquation.mifflinStJeor.rawValue,
            leanBodyMassKg: Double? = nil,
            hasCompletedQuickStart: Bool = false,
            useHealthSync: Bool = true,
            enableReminders: Bool = false,
            includeActiveCaloriesInMax: Bool = false,
            autoSaveToCatalog: Bool = true
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
            self.tdeeEquationRawValue = tdeeEquationRawValue
            self.leanBodyMassKg = leanBodyMassKg
            self.hasCompletedQuickStart = hasCompletedQuickStart
            self.useHealthSync = useHealthSync
            self.enableReminders = enableReminders
            self.includeActiveCaloriesInMax = includeActiveCaloriesInMax
            self.autoSaveToCatalog = autoSaveToCatalog

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

        var tdeeEquation: TDEEEquation {
            get { tdeeEquationRawValue.flatMap(TDEEEquation.init(rawValue:)) ?? .mifflinStJeor }
            set { tdeeEquationRawValue = newValue.rawValue }
        }

        func estimatedBMR() -> Double {
            switch tdeeEquation {
            case .mifflinStJeor:
                return mifflinStJeorBMR()
            case .harrisBenedict:
                switch biologicalSex {
                case .male:
                    return 88.362 + (13.397 * weightKg) + (4.799 * heightCm) - (5.677 * Double(age))
                case .female:
                    return 447.593 + (9.247 * weightKg) + (3.098 * heightCm) - (4.330 * Double(age))
                }
            case .katchMcArdle:
                guard let leanBodyMassKg, leanBodyMassKg > 0 else {
                    return mifflinStJeorBMR()
                }
                return 370 + (21.6 * leanBodyMassKg)
            }
        }

        private func mifflinStJeorBMR() -> Double {
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
