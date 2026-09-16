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

    var sharedModelContainer: ModelContainer = {
        print("DEBUG: Initializing SimplyTrack app with SwiftData")
        ensureAppSupportDirectoryExists()
        let schema = Schema(SimplyTrackSchemaV2.models)

        let persistentConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: SimplyTrackMigrationPlan.self,
                configurations: [persistentConfiguration]
            )
        } catch {
            // Recovery path for incompatible/corrupted stores after schema changes.
            ensureAppSupportDirectoryExists()
            let appSupport = appSupportURL
            let candidateStoreFiles = [
                appSupport.appending(path: "default.store"),
                appSupport.appending(path: "default.store-shm"),
                appSupport.appending(path: "default.store-wal")
            ]
            for fileURL in candidateStoreFiles {
                try? FileManager.default.removeItem(at: fileURL)
            }

            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: SimplyTrackMigrationPlan.self,
                    configurations: [persistentConfiguration]
                )
            } catch {
                preconditionFailure("Could not create persistent ModelContainer after recovery attempts: \(error)")
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
