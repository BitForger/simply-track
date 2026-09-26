//
//  WeightLossPace.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

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
