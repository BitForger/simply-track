//
//  BiologicalSex.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

enum BiologicalSex: String, CaseIterable, Identifiable {
    case female
    case male

    var id: String { rawValue }
}
