//
//  Calendar+GregorianSundayStart.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import Foundation

extension Calendar {
    static var gregorianSundayStart: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 1
        return calendar
    }

    func startOfWeekSunday(for date: Date) -> Date {
        let dayStart = startOfDay(for: date)
        let weekday = component(.weekday, from: dayStart)
        let daysFromSunday = (weekday - firstWeekday + 7) % 7
        return self.date(byAdding: .day, value: -daysFromSunday, to: dayStart) ?? dayStart
    }
}
