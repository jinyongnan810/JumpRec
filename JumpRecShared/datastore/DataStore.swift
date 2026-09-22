//
//  DataStore.swift
//  ListIt
//
//  Created by Yuunan kin on 2025/09/06.
//

import CloudKit
import CoreData
import Foundation
import Observation
import SwiftData

// MARK: - ModelContainer

extension ModelContainer {
    /// The app group used to keep the local SwiftData store accessible to the phone app and extensions.
    static let groupContainerIdentifier = "group.com.kinn.JumpRec"

    /// The iCloud container expected to back SwiftData's managed CloudKit sync.
    static let cloudKitContainerIdentifier = "iCloud.com.kinn.JumpRec"

    /// Returns the full schema used by the production store.
    static func makeSharedSchema() -> Schema {
        Schema([
            JumpSession.self,
            PersonalRecord.self,
            SessionRateSeries.self,
        ])
    }

    /// Returns the SwiftData configuration used by the production store.
    /// Keeping this in one place avoids the diagnostics path drifting away from the real store setup.
    static func makeSharedConfiguration() -> ModelConfiguration {
        ModelConfiguration(
            schema: makeSharedSchema(),
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier(groupContainerIdentifier),
            cloudKitDatabase: .private(cloudKitContainerIdentifier)
        )
    }

    /// Creates a shared ModelContainer with CloudKit sync enabled.
    static func createContainer() throws -> ModelContainer {
        let schema = makeSharedSchema()
        let modelConfiguration = makeSharedConfiguration()

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}

/// Singleton data store managing SwiftData persistence for the app.
@MainActor
@Observable
public final class MyDataStore {
    private enum DefaultsKey {
        static let unseenPersonalRecordKinds = "unseenPersonalRecordKinds"
    }

    // MARK: - Cloud Restore Diagnostics

    /// Describes the active phase of CloudKit synchronization.
    public enum CloudSyncPhase: Equatable {
        /// Not actively executing any CloudKit sync operations.
        case idle
        /// Verifying account or establishing connection to CloudKit.
        case connecting
        /// Actively fetching and downloading records from iCloud to the local device.
        case importing
        /// Uploading newly completed sessions or record changes to iCloud.
        case exporting
        /// The previous sync event ended with a failure.
        case failed(String)

        /// Human-readable label for UI indicators.
        public var title: String {
            switch self {
            case .idle:
                String(localized: "Idle")
            case .connecting:
                String(localized: "Connecting to iCloud...")
            case .importing:
                String(localized: "Downloading from iCloud...")
            case .exporting:
                String(localized: "Uploading to iCloud...")
            case .failed:
                String(localized: "Sync Failed")
            }
        }
    }

    /// Describes whether the current device can reach the expected iCloud account for CloudKit sync.
    public enum CloudAccountAvailability: String {
        case checking
        case available
        case unavailable
        case restricted
        case temporarilyUnavailable
        case couldNotDetermine

        /// Human-readable text for logs and UI diagnostics.
        var description: String {
            switch self {
            case .checking:
                "Checking iCloud account availability"
            case .available:
                "iCloud account is available"
            case .unavailable:
                "No iCloud account is signed in"
            case .restricted:
                "iCloud account access is restricted"
            case .temporarilyUnavailable:
                "iCloud account is temporarily unavailable"
            case .couldNotDetermine:
                "Unable to determine iCloud account availability"
            }
        }
    }

    /// Shared singleton instance.
    public static let shared: MyDataStore = {
        do {
            return try MyDataStore.makeSharedStore()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// The SwiftData model container managing persistent storage.
    public let modelContainer: ModelContainer

    /// Main context for performing data operations.
    public let modelContext: ModelContext

    /// Tracks the current CloudKit account status so empty-state UI can explain why history may be missing.
    public private(set) var cloudAccountAvailability: CloudAccountAvailability = .checking

    /// Detailed phase of CloudKit synchronization.
    public private(set) var cloudSyncPhase: CloudSyncPhase = .idle

    /// Whether an iCloud sync operation (setup, import, export, or account check) is actively running.
    public private(set) var isCloudSyncActive = false

    /// Timestamp of the last successful sync event (import or export).
    public private(set) var lastSyncDate: Date?

    /// Description of the latest sync error, if any occurred.
    public private(set) var lastSyncErrorDescription: String?

    /// Count of local JumpSession records currently present in the database.
    public private(set) var localSessionCount: Int = 0

    /// Tracks whether at least one session exists locally.
    public private(set) var hasLocalSessions: Bool = false

    /// Stores the best-known local persistence location for debugging uninstall and restore issues.
    public private(set) var storeLocationDescription = "Unknown"

    /// Tracks which exact record kinds were newly achieved so UI surfaces can explain the badge.
    public private(set) var unseenPersonalRecordKinds: [PersonalRecordKind] = []

    @ObservationIgnored
    private let defaults: UserDefaults

    /// Creates the shared store and applies one-time bootstrap work.
    private static func makeSharedStore() throws -> MyDataStore {
        let modelContainer = try ModelContainer.createContainer()
        let store = MyDataStore(modelContainer: modelContainer)
        #if DEBUG
            store.removeDebugSessionsBelowMinimumJumpCountIfNeeded()
        #endif
//        store.backfillPersonalRecordsIfNeeded()
        store.logPersistenceConfiguration()
        store.refreshLocalSessionCount()
        store.observeCloudAccountChanges()
        store.observeCloudKitEvents()
        store.observeRemoteStoreChanges()
        store.refreshCloudDiagnostics()
        print("[DataStore] ModelContainer and ModelContext initialized successfully")
        return store
    }

    private init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        defaults = UserDefaults(suiteName: ModelContainer.groupContainerIdentifier) ?? .standard
        modelContext = modelContainer.mainContext
        modelContext.autosaveEnabled = true
        unseenPersonalRecordKinds = (defaults.stringArray(forKey: DefaultsKey.unseenPersonalRecordKinds) ?? [])
            .compactMap(PersonalRecordKind.init(rawValue:))
        let initialCount = (try? modelContainer.mainContext.fetchCount(FetchDescriptor<JumpSession>())) ?? 0
        localSessionCount = initialCount
        hasLocalSessions = initialCount > 0
    }

    /// Saves pending context changes when needed.
    func saveContextIfNeeded() {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    /// Marks that new or improved personal records are waiting to be viewed by the user.
    public func markUnseenPersonalRecordUpdates(_ kinds: [PersonalRecordKind]) {
        guard !kinds.isEmpty else { return }

        var mergedKinds = unseenPersonalRecordKinds
        for kind in kinds where !mergedKinds.contains(kind) {
            mergedKinds.append(kind)
        }
        updateUnseenPersonalRecordUpdates(mergedKinds)
    }

    /// Clears the personal-record badge after the records sheet has been opened and closed.
    public func clearUnseenPersonalRecordUpdates() {
        updateUnseenPersonalRecordUpdates([])
    }

    /// Refreshes iCloud-related diagnostics on demand.
    /// This is safe to call whenever the app becomes active because it only updates observable status fields and logs.
    public func refreshCloudDiagnostics() {
        Task { [weak self] in
            guard let self else { return }
            await updateCloudAccountAvailability()
        }
    }

    /// Refreshes the local session count from the persistent store and updates observable flags.
    /// This is called whenever a CloudKit import finishes, a remote change notification fires, or manual refresh runs.
    public func refreshLocalSessionCount() {
        let count = fetchSessionCount()
        localSessionCount = count
        hasLocalSessions = count > 0
    }

    /// Manually triggers a re-check of the iCloud account and model store.
    /// This is invoked by pull-to-refresh on history views.
    public func manualSyncCheck() async {
        isCloudSyncActive = true
        cloudSyncPhase = .connecting
        await updateCloudAccountAvailability()
        refreshLocalSessionCount()

        // Brief delay so pull-to-refresh animation feels natural
        try? await Task.sleep(for: .milliseconds(400))

        refreshLocalSessionCount()
        if cloudSyncPhase == .connecting {
            cloudSyncPhase = .idle
            isCloudSyncActive = false
        }
    }

    // MARK: - Private Helpers

    /// Logs the concrete storage location and the expected CloudKit container so uninstall-related behavior is easier to diagnose.
    private func logPersistenceConfiguration() {
        let configuration = ModelContainer.makeSharedConfiguration()
        let groupContainerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: ModelContainer.groupContainerIdentifier
        )
        storeLocationDescription = configuration.url.path(percentEncoded: false)
        if storeLocationDescription.isEmpty {
            storeLocationDescription = groupContainerURL?.path(percentEncoded: false) ?? "Unavailable"
        }

        print("[DataStore] Store URL: \(storeLocationDescription)")
        print("[DataStore] App group container: \(ModelContainer.groupContainerIdentifier)")
        print("[DataStore] Expected CloudKit container: \(ModelContainer.cloudKitContainerIdentifier)")
    }

    /// Stores the unseen record kinds in both observable state and app-group defaults.
    private func updateUnseenPersonalRecordUpdates(_ kinds: [PersonalRecordKind]) {
        guard unseenPersonalRecordKinds != kinds else { return }
        unseenPersonalRecordKinds = kinds
        defaults.set(kinds.map(\.rawValue), forKey: DefaultsKey.unseenPersonalRecordKinds)
    }

    /// Updates observable state and diagnostics in response to NSPersistentCloudKitContainer lifecycle events.
    private func handleCloudKitEvent(_ event: NSPersistentCloudKitContainer.Event) {
        let isOngoing = event.endDate == nil
        print("[DataStore] CloudKit event: type=\(event.type), ongoing=\(isOngoing), succeeded=\(event.succeeded), error=\(String(describing: event.error))")

        if isOngoing {
            isCloudSyncActive = true
            switch event.type {
            case .setup:
                cloudSyncPhase = .connecting
            case .import:
                cloudSyncPhase = .importing
            case .export:
                cloudSyncPhase = .exporting
            @unknown default:
                cloudSyncPhase = .connecting
            }
        } else {
            isCloudSyncActive = false

            if event.succeeded {
                lastSyncDate = event.endDate ?? Date()
                lastSyncErrorDescription = nil
                cloudSyncPhase = .idle
                refreshLocalSessionCount()
            } else {
                let errorDesc = event.error?.localizedDescription ?? "Unknown sync error"
                lastSyncErrorDescription = errorDesc
                cloudSyncPhase = .failed(errorDesc)
                print("[DataStore] CloudKit sync event failed: \(errorDesc)")
            }
        }
    }

    /// Observes CloudKit export, import, and setup events emitted by NSPersistentCloudKitContainer.
    private func observeCloudKitEvents() {
        NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey] as? NSPersistentCloudKitContainer.Event else {
                    return
                }
                self.handleCloudKitEvent(event)
            }
        }
    }

    /// Listens for store remote changes so UI state updates immediately when CloudKit merges remote records.
    private func observeRemoteStoreChanges() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name.NSPersistentStoreRemoteChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                print("[DataStore] Remote store change received, refreshing local session state")
                self.refreshLocalSessionCount()
            }
        }
    }

    /// Reads the current local session count without relying on view state.
    private func fetchSessionCount() -> Int {
        let descriptor = FetchDescriptor<JumpSession>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Re-checks the active iCloud account and logs the exact status for startup diagnostics.
    private func updateCloudAccountAvailability() async {
        cloudAccountAvailability = .checking

        let ubiquityTokenAvailable = FileManager.default.ubiquityIdentityToken != nil
        print("[DataStore] NSUbiquitousKeyValueStore token available: \(ubiquityTokenAvailable)")

        do {
            let status = try await CKContainer(identifier: ModelContainer.cloudKitContainerIdentifier).accountStatus()
            let mappedStatus = map(status)
            cloudAccountAvailability = mappedStatus
            print("[DataStore] CloudKit account status: \(mappedStatus.description)")
        } catch {
            cloudAccountAvailability = .couldNotDetermine
            print("[DataStore] Failed to determine CloudKit account status: \(error.localizedDescription)")
        }
    }

    /// Listens for account changes so diagnostics stay accurate if the user signs in or out while the app is installed.
    private func observeCloudAccountChanges() {
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshCloudDiagnostics()
            }
        }
    }

    /// Converts CloudKit's account state into a smaller UI-friendly status enum.
    private func map(_ status: CKAccountStatus) -> CloudAccountAvailability {
        switch status {
        case .available:
            .available
        case .noAccount:
            .unavailable
        case .restricted:
            .restricted
        case .temporarilyUnavailable:
            .temporarilyUnavailable
        case .couldNotDetermine:
            .couldNotDetermine
        @unknown default:
            .couldNotDetermine
        }
    }
}
