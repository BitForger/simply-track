//
//  simply_trackApp.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData

// MARK: - Persistence Status Tracking
/// Tracks the current data persistence mode and any associated errors.
@Observable final class PersistenceStatus {
    enum Mode: Equatable {
        case cloudKitBacked
        case localOnly
    }

    var mode: Mode = .cloudKitBacked
    var error: PersistenceError?
    var isCloudKitQuotaError: Bool = false

    enum PersistenceError: LocalizedError {
        case cloudKitQuotaExceeded
        case cloudKitUnavailable(String)
        case localStorageFailed(String)

        var errorDescription: String? {
            switch self {
            case .cloudKitQuotaExceeded:
                return "iCloud Storage Full"
            case .cloudKitUnavailable(let details):
                return "CloudKit Unavailable: \(details)"
            case .localStorageFailed(let details):
                return "Local Storage Error: \(details)"
            }
        }

        var failureReason: String? {
            switch self {
            case .cloudKitQuotaExceeded:
                return "You don't have enough iCloud storage space. Free up space in iCloud Settings, then relaunch the app."
            case .cloudKitUnavailable:
                return "CloudKit sync is disabled. Data is stored locally only."
            case .localStorageFailed(let details):
                return details
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .cloudKitQuotaExceeded:
                return "Delete files or photos from iCloud, or upgrade your iCloud storage plan."
            case .cloudKitUnavailable:
                return "Check your internet connection and iCloud account settings."
            case .localStorageFailed:
                return "Try restarting the app. If the problem persists, contact support."
            }
        }
    }
}

@main
struct simply_trackApp: App {
    @State private var persistenceStatus = PersistenceStatus()

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

    /// Backs up the persistent store asynchronously in the background to avoid blocking app startup.
    /// This method returns immediately; actual backup happens on a background thread.
    private static func backupPersistentStoreIfPresent() {
        // Dispatch to a background thread to avoid blocking the main thread.
        // App initialization can proceed while backups happen in the background.
        DispatchQueue.global(qos: .background).async {
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
                    print("INFO: Successfully backed up \(storeURL.lastPathComponent)")
                } catch {
                    print("Warning: Could not back up store file \(storeURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    /// Detects if an error is due to CloudKit storage quota being exceeded.
    private static func isCloudKitQuotaError(_ error: Error) -> Bool {
        if let nsError = error as? NSError {
            // CloudKit error codes: https://developer.apple.com/documentation/cloudkit/ckerrorcode
            // 5 = quotaExceeded (within a specific operation)
            // 10 = limitExceeded (general quota exceeded)
            let isQuotaCode = nsError.code == 5 || nsError.code == 10
            let isCloudKitDomain = nsError.domain == "CKErrorDomain" || nsError.domain == "com.apple.cloudkit.error"
            return isQuotaCode && isCloudKitDomain
        }
        return false
    }

    /// Creates and returns a ModelContainer, updating persistenceStatus on fallback.
    private func createModelContainer() -> ModelContainer {
        print("DEBUG: Initializing SimplyTrack app with SwiftData")
        Self.ensureAppSupportDirectoryExists()
        Self.backupPersistentStoreIfPresent()

        let schema = Schema(SimplyTrackSchemaV6.models)

        let cloudBackedPersistentConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let localPersistentConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        // Step 1: Try CloudKit-backed store
        do {
            print("INFO: Attempting to initialize CloudKit-backed SwiftData store")
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SimplyTrackMigrationPlan.self,
                configurations: [cloudBackedPersistentConfiguration]
            )
            persistenceStatus.mode = .cloudKitBacked
            persistenceStatus.error = nil
            persistenceStatus.isCloudKitQuotaError = false
            print("INFO: Successfully initialized CloudKit-backed store")
            return container
        } catch {
            // Detect if this is a storage quota error
            let isQuotaError = Self.isCloudKitQuotaError(error)
            persistenceStatus.isCloudKitQuotaError = isQuotaError

            if isQuotaError {
                print("ERROR: CloudKit storage quota exceeded: \(error)")
                persistenceStatus.error = .cloudKitQuotaExceeded
            } else {
                print("WARNING: Failed to open CloudKit-backed SwiftData store: \(error)")
                persistenceStatus.error = .cloudKitUnavailable(error.localizedDescription)
            }
        }

        // Step 2: Try local-only persistent store
        do {
            print("INFO: Attempting to initialize local-only persistent SwiftData store")
            let container = try ModelContainer(
                for: schema,
                migrationPlan: SimplyTrackMigrationPlan.self,
                configurations: [localPersistentConfiguration]
            )
            persistenceStatus.mode = .localOnly
            print("INFO: Successfully initialized local-only persistent store")
            return container
        } catch {
            print("ERROR: Failed to open local persistent SwiftData store: \(error)")
            persistenceStatus.error = .localStorageFailed(error.localizedDescription)

            // CRITICAL: Do NOT silently fall back to in-memory storage.
            // Users must be aware their data won't persist between launches.
            // Show a visible error and crash rather than silently losing data.
            fatalError(
                "Critical: Local data persistence failed and we cannot safely continue. "
                + "This prevents data loss. Error: \(error.localizedDescription)\n"
                + "Details: Check iCloud settings, available storage space, and app file system permissions."
            )
        }
    }

    var sharedModelContainer: ModelContainer {
        createModelContainer()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(persistenceStatus)
        }
        .modelContainer(sharedModelContainer)
    }
}
