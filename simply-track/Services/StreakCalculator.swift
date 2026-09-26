//
//  StreakCalculator.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

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
