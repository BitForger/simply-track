//
//  CalorieSummaryCalculator.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

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
