//
//  EntryPayloads.swift
//  simply-track
//
//  Created by Noah on 10/2/26.
//

import Foundation

struct AddFoodEntryPayload: Hashable {
    let foodName: String
    let amountDescription: String
    let calories: Double
    let consumedAt: Date
    let saveToCatalog: Bool
}

struct CalorieEntryPayload: Hashable {
    var id: UUID
    var foodName: String
    var amountDescription: String
    var calories: Double
    var consumedAt: Date
    var updatedAt: Date
    var source: String
    var healthKitSampleIdentifier: String?

    init(id: UUID = UUID(), foodName: String, amountDescription: String, calories: Double, consumedAt: Date, updatedAt: Date, source: String, healthKitSampleIdentifier: String? = nil) {
        self.id = id
        self.foodName = foodName
        self.amountDescription = amountDescription
        self.calories = calories
        self.consumedAt = consumedAt
        self.updatedAt = updatedAt
        self.source = source
        self.healthKitSampleIdentifier = healthKitSampleIdentifier
    }

    init(_ entry: FoodEntry) {
        self.init(
            id: entry.id,
            foodName: entry.foodName,
            amountDescription: entry.amountDescription,
            calories: entry.calories,
            consumedAt: entry.consumedAt,
            updatedAt: entry.updatedAt,
            source: entry.source,
            healthKitSampleIdentifier: entry.healthKitSampleIdentifier
        )
    }
}

struct ActiveCaloriesReadResult {
    let calories: Double
    let fallbackNote: String?
}
