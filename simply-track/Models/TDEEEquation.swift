//
//  TDEEEquation.swift
//  simply-track
//
//  Created by Noah on 9/25/26.
//

import Foundation

enum TDEEEquation: String, CaseIterable, Identifiable {
    case mifflinStJeor
    case harrisBenedict
    case katchMcArdle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mifflinStJeor: return "Mifflin-St Jeor"
        case .harrisBenedict: return "Harris-Benedict"
        case .katchMcArdle: return "Katch-McArdle"
        }
    }

    /// Short pros/cons summary shown as hint text under the equation picker.
    var summary: String {
        switch self {
        case .mifflinStJeor:
            return "Pros: Most accurate for the general population; the modern standard. Cons: Less precise for very muscular or very lean individuals."
        case .harrisBenedict:
            return "Pros: Long-standing, well-known formula. Cons: Tends to overestimate BMR compared to Mifflin-St Jeor, especially at higher body fat levels."
        case .katchMcArdle:
            return "Pros: Most accurate for lean or muscular individuals since it uses lean body mass directly. Cons: Requires knowing your lean body mass; falls back to Mifflin-St Jeor until it's provided."
        }
    }
}
