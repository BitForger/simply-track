import Foundation

enum LegacyProfilePreferencesMigrationService {
    static let markerKey = "didMigratePreferencesToUserProfileV1"

    static func migrateIfNeeded(profile: UserProfile, defaults: UserDefaults = .standard) {
        guard defaults.bool(forKey: markerKey) == false else {
            return
        }

        if let value = defaults.object(forKey: "hasCompletedQuickStart") as? Bool {
            profile.hasCompletedQuickStart = value
        }
        if let value = defaults.object(forKey: "useHealthSync") as? Bool {
            profile.useHealthSync = value
        } else if let value = defaults.object(forKey: "useCloudKitSync") as? Bool {
            profile.useHealthSync = value
        }
        if let value = defaults.object(forKey: "enableReminders") as? Bool {
            profile.enableReminders = value
        }
        if let value = defaults.object(forKey: "includeActiveCaloriesInMax") as? Bool {
            profile.includeActiveCaloriesInMax = value
        }
        if let value = defaults.object(forKey: "autoSaveToCatalog") as? Bool {
            profile.autoSaveToCatalog = value
        }

        defaults.set(true, forKey: markerKey)
    }
}
