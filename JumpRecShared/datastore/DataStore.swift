//
//  DataStore.swift
//  ListIt
//
//  Created by Yuunan kin on 2025/09/06.
//

import CloudKit
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
            cloudKitDatabase: .automatic
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

    /// Reflects whether the app is still giving CloudKit time to repopulate an empty local store.
    public private(set) var isAwaitingInitialCloudRestore = false

    /// Stores the best-known local persistence location for debugging uninstall and restore issues.
    public private(set) var storeLocationDescription = "Unknown"

    /// Tracks which exact record kinds were newly achieved so UI surfaces can explain the badge.
    public private(set) var unseenPersonalRecordKinds: [PersonalRecordKind] = []

    @ObservationIgnored
    private var cloudRestoreTask: Task<Void, Never>?
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
        store.observeCloudAccountChanges()
        store.refreshCloudDiagnostics()
        store.startInitialCloudRestoreWindowIfNeeded()
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
    }

    deinit {
        cloudRestoreTask?.cancel()
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

    /// Tells the history screen whether it should show a sync-in-progress explanation while the library is still empty.
    public func updateInitialCloudRestoreState(hasSessions: Bool) {
        if hasSessions {
            cloudRestoreTask?.cancel()
            cloudRestoreTask = nil
            isAwaitingInitialCloudRestore = false
        } else if cloudAccountAvailability == .available {
            startInitialCloudRestoreWindowIfNeeded()
        } else {
            isAwaitingInitialCloudRestore = false
        }
    }

    /// Returns copy tailored for empty-library messaging.
    public var cloudRestoreStatusMessage: String {
        if isAwaitingInitialCloudRestore {
            return String(
                localized: "Syncing from iCloud. Your saved sessions may take a moment to reappear after reinstalling the app."
            )
        }

        switch cloudAccountAvailability {
        case .available:
            return String(
                localized: "No cloud data restored yet. If you recently reinstalled the app, leave it open for a bit longer so iCloud can finish syncing."
            )
        case .checking:
            return String(localized: "Checking iCloud availability for your saved sessions.")
        case .unavailable:
            return String(
                localized: "No iCloud account is currently signed in, so previous cloud-backed sessions cannot be restored on this device yet."
            )
        case .restricted:
            return String(
                localized: "iCloud access is restricted on this device, so cloud-backed sessions cannot be restored right now."
            )
        case .temporarilyUnavailable:
            return String(
                localized: "iCloud is temporarily unavailable. Previously synced sessions may reappear once the account becomes reachable again."
            )
        case .couldNotDetermine:
            return String(
                localized: "The app could not confirm iCloud availability, so session restore status is unknown."
            )
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

    /// Starts a short grace period for CloudKit to repopulate an empty store after app install or reinstall.
    /// SwiftData mirroring is eventual, so immediately showing a permanent empty state is misleading when data is still downloading.
    private func startInitialCloudRestoreWindowIfNeeded() {
        guard cloudAccountAvailability == .available else {
            isAwaitingInitialCloudRestore = false
            cloudRestoreTask?.cancel()
            cloudRestoreTask = nil
            return
        }

        guard fetchSessionCount() == 0 else {
            isAwaitingInitialCloudRestore = false
            cloudRestoreTask?.cancel()
            cloudRestoreTask = nil
            return
        }

        guard cloudRestoreTask == nil else { return }

        isAwaitingInitialCloudRestore = true
        cloudRestoreTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self, !Task.isCancelled else { return }
            isAwaitingInitialCloudRestore = false
            cloudRestoreTask = nil
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

        startInitialCloudRestoreWindowIfNeeded()
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
