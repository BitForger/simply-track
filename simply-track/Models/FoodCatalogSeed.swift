//
//  FoodCatalogSeed.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

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
