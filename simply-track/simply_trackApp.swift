//
//  simply_trackApp.swift
//  simply-track
//
//  Created by Noah on 8/27/26.
//

import SwiftUI
import SwiftData
import SQLite3

// MARK: - Persistence Status Tracking
/// Tracks the current data persistence mode and any associated errors.
@Observable final class PersistenceStatus {
    enum Mode: Equatable {
        case cloudKitBacked
        case localOnly
    }

    var mode: Mode = .localOnly
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
                return "CloudKit sync is unavailable. Data is stored locally on this device."
            case .localStorageFailed(let details):
                return details
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .cloudKitQuotaExceeded:
                return "Delete files or photos from iCloud, or upgrade your iCloud storage plan."
            case .cloudKitUnavailable:
                return "You can keep using the app locally, or turn CloudKit sync back on in Settings after checking your iCloud account settings."
            case .localStorageFailed:
                return "Try restarting the app. If the problem persists, contact support."
            }
        }
    }
}

@main
struct simply_trackApp: App {
    @State private var persistenceStatus: PersistenceStatus
    private let sharedModelContainer: ModelContainer

    private static let cloudKitPersistenceEnabledKey = "useCloudKitPersistence"

    init() {
        let status = PersistenceStatus()
        _persistenceStatus = State(initialValue: status)
        sharedModelContainer = Self.createModelContainer(persistenceStatus: status)
    }

    private static let appSupportURL = URL.applicationSupportDirectory
    private static let persistentStoreBaseName = "default.store"
    private static let backupDirectoryName = "StoreBackups"
    private static let maxRetainedBackups = 3
    private static let maxBackupAgeDays = 30

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

    /// Creates a transactionally consistent SQLite snapshot and prunes old backups.
    /// This should only be invoked for major events (e.g. store recovery paths), not every launch.
    private static func backupPersistentStoreIfPresent(reason: String) {
        let fileManager = FileManager.default
        let primaryStoreURL = appSupportURL.appendingPathComponent(persistentStoreBaseName)
        guard fileManager.fileExists(atPath: primaryStoreURL.path) else { return }

        let backupDirectory = appSupportURL.appendingPathComponent(backupDirectoryName, isDirectory: true)

        do {
            try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
            try pruneBackups(in: backupDirectory, fileManager: fileManager)

            let timestamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
            let backupName = "\(persistentStoreBaseName).\(reason).\(timestamp).sqlite"
            let backupURL = backupDirectory.appendingPathComponent(backupName)

            if fileManager.fileExists(atPath: backupURL.path) {
                try fileManager.removeItem(at: backupURL)
            }

            try createSQLiteSnapshot(from: primaryStoreURL, to: backupURL)
            try pruneBackups(in: backupDirectory, fileManager: fileManager)
            print("INFO: Created persistent store backup: \(backupName)")
        } catch {
            print("Warning: Could not create persistent store backup (\(reason)): \(error)")
        }
    }

    private static func createSQLiteSnapshot(from sourceURL: URL, to destinationURL: URL) throws {
        var sourceDB: OpaquePointer?
        var destinationDB: OpaquePointer?

        let sourceOpenResult = sqlite3_open_v2(sourceURL.path, &sourceDB, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil)
        guard sourceOpenResult == SQLITE_OK, let sourceDB else {
            throw sqliteError(resultCode: sourceOpenResult, database: sourceDB, context: "opening source store")
        }
        defer { sqlite3_close(sourceDB) }

        let destinationOpenResult = sqlite3_open_v2(destinationURL.path, &destinationDB, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil)
        guard destinationOpenResult == SQLITE_OK, let destinationDB else {
            throw sqliteError(resultCode: destinationOpenResult, database: destinationDB, context: "opening backup destination")
        }
        defer { sqlite3_close(destinationDB) }

        guard let backupHandle = sqlite3_backup_init(destinationDB, "main", sourceDB, "main") else {
            throw sqliteError(resultCode: sqlite3_errcode(destinationDB), database: destinationDB, context: "initializing sqlite backup")
        }
        defer { sqlite3_backup_finish(backupHandle) }

        let stepResult = sqlite3_backup_step(backupHandle, -1)
        guard stepResult == SQLITE_DONE else {
            throw sqliteError(resultCode: stepResult, database: destinationDB, context: "copying sqlite backup")
        }
    }

    private static func pruneBackups(in backupDirectory: URL, fileManager: FileManager) throws {
        let backupURLs = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        let now = Date()
        let maxAgeInterval = TimeInterval(maxBackupAgeDays * 24 * 60 * 60)

        // Remove backups older than the age cap first.
        for backupURL in backupURLs {
            let values = try backupURL.resourceValues(forKeys: [.contentModificationDateKey])
            let modifiedDate = values.contentModificationDate ?? .distantPast
            if now.timeIntervalSince(modifiedDate) > maxAgeInterval {
                try fileManager.removeItem(at: backupURL)
            }
        }

        // Re-list after age pruning, then enforce max count by deleting oldest first.
        var retained = try fileManager.contentsOfDirectory(
            at: backupDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )

        retained.sort {
            let lhsDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        if retained.count > maxRetainedBackups {
            let overflowCount = retained.count - maxRetainedBackups
            for url in retained.prefix(overflowCount) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    private static func sqliteError(resultCode: Int32, database: OpaquePointer?, context: String) -> NSError {
        let message = database.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "Unknown SQLite error"
        return NSError(
            domain: "SimplyTrack.SQLiteBackup",
            code: Int(resultCode),
            userInfo: [NSLocalizedDescriptionKey: "\(context): \(message)"]
        )
    }

    /// Removes SQLite sidecar files that can prevent a healthy local store from opening after a failed launch.
    private static func removePersistentStoreSidecars() {
        let fileManager = FileManager.default
        for storeURL in persistentStoreURLs where storeURL.lastPathComponent != persistentStoreBaseName {
            if fileManager.fileExists(atPath: storeURL.path) {
                do {
                    try fileManager.removeItem(at: storeURL)
                    print("INFO: Removed stale persistent store sidecar: \(storeURL.lastPathComponent)")
                } catch {
                    print("Warning: Could not remove sidecar \(storeURL.lastPathComponent): \(error)")
                }
            }
        }
    }

    /// Detects if an error is due to CloudKit storage quota being exceeded.
    private static func isCloudKitQuotaError(_ error: Error) -> Bool {
        let nsError = error as NSError
        // CloudKit error codes: https://developer.apple.com/documentation/cloudkit/ckerrorcode
        // 5 = quotaExceeded (within a specific operation)
        // 10 = limitExceeded (general quota exceeded)
        let isQuotaCode = nsError.code == 5 || nsError.code == 10
        let isCloudKitDomain = nsError.domain == "CKErrorDomain" || nsError.domain == "com.apple.cloudkit.error"
        return isQuotaCode && isCloudKitDomain
    }

    private static var isCloudKitPersistenceEnabled: Bool {
        UserDefaults.standard.bool(forKey: cloudKitPersistenceEnabledKey)
    }

    /// Creates and returns a ModelContainer, updating persistenceStatus for the active storage mode.
    private static func createModelContainer(persistenceStatus: PersistenceStatus) -> ModelContainer {
        print("DEBUG: Initializing SimplyTrack app with SwiftData")
        Self.ensureAppSupportDirectoryExists()

        let schema = Schema(SimplyTrackSchemaV7.models)
        let useCloudKit = isCloudKitPersistenceEnabled

        let cloudBackedPersistentConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )

        let localPersistentConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        if useCloudKit {
            do {
                print("INFO: Attempting to initialize CloudKit-backed SwiftData store")
                let container = try ModelContainer(
                    for: schema,
                    configurations: [cloudBackedPersistentConfiguration]
                )
                persistenceStatus.mode = .cloudKitBacked
                persistenceStatus.error = nil
                persistenceStatus.isCloudKitQuotaError = false
                print("INFO: Successfully initialized CloudKit-backed store")
                return container
            } catch {
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
        }

        // Local on-disk store is the default and the fallback when CloudKit is off or unavailable.
        do {
            print("INFO: Attempting to initialize local-only persistent SwiftData store")
            let container = try ModelContainer(
                for: schema,
                configurations: [localPersistentConfiguration]
            )
            persistenceStatus.mode = .localOnly
            if !useCloudKit {
                persistenceStatus.error = nil
            }
            print("INFO: Successfully initialized local-only persistent store")
            return container
        } catch {
            print("ERROR: Failed to open local persistent SwiftData store: \(error)")

            print("INFO: Capturing store backup before local recovery cleanup")
            Self.backupPersistentStoreIfPresent(reason: "pre-recovery")

            print("INFO: Attempting to recover local store by clearing stale SQLite sidecar files")
            Self.removePersistentStoreSidecars()

            do {
                let recoveredContainer = try ModelContainer(
                    for: schema,
                    configurations: [localPersistentConfiguration]
                )
                persistenceStatus.mode = .localOnly
                if !useCloudKit {
                    persistenceStatus.error = nil
                }
                persistenceStatus.isCloudKitQuotaError = false
                print("INFO: Successfully recovered local-only persistent store after cleanup")
                return recoveredContainer
            } catch {
                print("ERROR: Local persistent store recovery failed: \(error)")
                persistenceStatus.mode = .localOnly
                persistenceStatus.error = .localStorageFailed(error.localizedDescription)
                preconditionFailure("Could not create a persistent ModelContainer after local storage recovery failure: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(persistenceStatus)
        }
        .modelContainer(sharedModelContainer)
    }
}
