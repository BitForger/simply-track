//
//  NutritionGoal.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

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
