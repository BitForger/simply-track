//
//  simply_trackApp.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData

@main
struct simply_trackApp: App {
    private static let appSupportURL = URL.applicationSupportDirectory
    private static let persistentStoreBaseName = "default.store"

    private static var persistentStoreURLs: [URL] {
        [
            appSupportURL.appendingPathComponent(persistentStoreBaseName),
            appSupportURL.appendingPathComponent("\(persistentStoreBaseName)-shm"),
            appSupportURL.appendingPathComponent("\(persistentStoreBaseName)-wal")
        ]
    }

    private static func ensureAppSupportDirectoryExists() {
        do {
            try FileManager.default.createDirectory(
                at: appSupportURL,
                withIntermediateDirectories: true
            )
        } catch {
            // Keep startup resilient; persistent store setup handles failure explicitly.
            print("Warning: Could not ensure Application Support directory: \(error)")
        }
    }

    private static func backupPersistentStoreIfPresent() {
        let fileManager = FileManager.default
        let backupDirectory = appSupportURL.appendingPathComponent("StoreBackups", isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        } catch {
            print("Warning: Could not create store backup directory: \(error)")
            return
        }

        let timestamp = Int(Date().timeIntervalSince1970)
        for storeURL in persistentStoreURLs where fileManager.fileExists(atPath: storeURL.path) {
            let backupName = "\(storeURL.lastPathComponent).\(timestamp).backup"
            let backupURL = backupDirectory.appendingPathComponent(backupName)

            do {
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.copyItem(at: storeURL, to: backupURL)
            } catch {
                print("Warning: Could not back up store file \(storeURL.lastPathComponent): \(error)")
            }
        }
    }

    var sharedModelContainer: ModelContainer = {
        print("DEBUG: Initializing SimplyTrack app with SwiftData")
        ensureAppSupportDirectoryExists()
        backupPersistentStoreIfPresent()
        // IMPORTANT: Always use the CURRENT (latest) versioned schema here, matching the
        // final version in SimplyTrackMigrationPlan.schemas. The FoodEntry/FoodCatalogItem/
        // UserProfile typealiases point to this same version. Registering an older schema
        // version's model classes here causes a Swift type-identity mismatch with the rest
        // of the app (which uses the typealiases), leading to runtime crashes like
        // "Failed to cast model ...SimplyTrackSchemaV6.FoodEntry ... to FoodEntry".
        let schema = Schema(SimplyTrackSchemaV6.models)

        let cloudBackedPersistentConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let localPersistentConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SimplyTrackMigrationPlan.self,
                configurations: [cloudBackedPersistentConfiguration]
            )
        } catch {
            print("Warning: Failed to open CloudKit-backed SwiftData store. Retrying with local-only persistence. Underlying error: \(error)")

            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: SimplyTrackMigrationPlan.self,
                    configurations: [localPersistentConfiguration]
                )
            } catch {
                // Never delete persistent files automatically; preserve user data across migration failures.
                print("Error: Failed to open local persistent SwiftData store. Falling back to in-memory store. Underlying error: \(error)")

                let inMemoryConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
                do {
                    return try ModelContainer(
                        for: schema,
                        migrationPlan: SimplyTrackMigrationPlan.self,
                        configurations: [inMemoryConfiguration]
                    )
                } catch {
                    preconditionFailure("Could not create ModelContainer (CloudKit, local persistent, and in-memory attempts all failed): \(error)")
                }
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
