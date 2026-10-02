//
//  ReminderManager.swift
//  simply-track
//
//  Created by Noah on 10/2/26.
//

import Foundation
import UserNotifications

actor ReminderManager {
    private let reminderIdentifier = "daily-calorie-log-reminder"

    func enableDefaultReminder() async throws {
        let center = UNUserNotificationCenter.current()
        let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        guard granted else { return }

        let content = UNMutableNotificationContent()
        content.title = "Log your calories"
        content.body = "A quick log now helps keep your weekly target on track."
        content.sound = .default

        var components = DateComponents()
        components.hour = 20
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: reminderIdentifier, content: content, trigger: trigger)

        center.removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
        try await center.add(request)
    }

    func disableReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [reminderIdentifier])
    }
}
