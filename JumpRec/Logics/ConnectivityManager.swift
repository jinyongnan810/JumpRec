//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by kinn on 2025/09/23.
//

import Foundation
import SwiftData
import WatchConnectivity

/// Manages WatchConnectivity session state, settings sync, and completed-session transfers.
@Observable
@MainActor
final class ConnectivityManager: NSObject, WCSessionDelegate {
    /// Shared singleton used across the iPhone app.
    static let shared = ConnectivityManager()

    /// ⭐️The active WatchConnectivity session.
    private let session: WCSession = .default

    /// Indicates whether WatchConnectivity is supported on this device.
    var isSupported: Bool = WCSession.isSupported()
    /// Indicates whether an Apple Watch is paired.
    var isPaired: Bool = false
    /// Indicates whether the watch app is installed.
    var isWatchAppInstalled: Bool = false
    /// Indicates whether the companion watch app is reachable.
    var isReachable: Bool = false
    /// Stores the latest WatchConnectivity activation state.
    var activationState: WCSessionActivationState = .notActivated
    /// Delivers fully reconstructed sessions received from Apple Watch.
    var onCompletedSessionReceived: ((Date, Date, Int, Double, [TimeInterval], Int?, Int?, JumpSession, [PersonalRecordKind]) -> Void)?
    var onWorkoutStartCancelled: (() -> Void)?
    /// Delivers lifecycle events before HealthKit mirroring is ready.
    var onWorkoutEventReceived: ((MirroredWorkoutPayload) -> Void)?
    #if DEBUG
        /// Delivers a received Watch motion CSV local URL and optional session start timestamp.
        var onMotionCSVReceived: ((URL, Date?) -> Void)?
    #endif
    /// ⭐️Persists synced settings in the shared ubiquitous key-value store.
    private let settingsStore = NSUbiquitousKeyValueStore.default
    /// Performs potentially delayed iCloud container resolution and file writes away from UI state.
    private let cloudCSVExporter = CloudCSVExporter()
    /// Tracks an entitlement sync that occurred before WatchConnectivity finished activating or installing.
    @ObservationIgnored
    private var hasPendingEntitlementTransfer = false
    /// Observes verified entitlement updates so Watch sync runs even outside ContentView's lifecycle.
    @ObservationIgnored
    private var entitlementObserver: NSObjectProtocol?

    /// Configures and activates the shared connectivity session.
    override private init() {
        super.init()
        entitlementObserver = NotificationCenter.default.addObserver(
            forName: .jumpRecEntitlementDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let forceDurableTransfer = notification.userInfo?["forceDurableTransfer"] as? Bool ?? false
            Task { @MainActor [weak self] in
                self?.syncCurrentEntitlementToWatch(transferDurably: forceDurableTransfer)
            }
        }
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    /// Refreshes cached Watch flags from the active session when already activated.
    func refreshStateIfActivated() {
        guard isSupported, session.activationState == .activated else { return }
        isPaired = session.isPaired
        isWatchAppInstalled = session.isWatchAppInstalled
        isReachable = session.isReachable
    }

    // MARK: - WCSessionDelegate

    /// Handles WatchConnectivity activation completion and refreshes local session flags.
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            print("[WatchConnectivityManager] Activation failed with error: \(error.localizedDescription)")
        } else {
            print("[WatchConnectivityManager] Activation completed with state: \(activationState.rawValue)")
        }

        // Snapshot WCSession values on its callback thread before updating main-actor state.
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.activationState = activationState
            self.isPaired = isPaired
            self.isWatchAppInstalled = isWatchAppInstalled
            self.isReachable = isReachable
            if activationState == .activated, hasPendingEntitlementTransfer {
                syncCurrentEntitlementToWatch(transferDurably: true)
            }
        }
    }

    /// Updates reachability when the watch app becomes reachable or unreachable.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("[WatchConnectivityManager] Session reachability changed: \(isReachable)")
        Task { @MainActor [weak self] in
            self?.isReachable = isReachable
            if isReachable {
                self?.sendCurrentEntitlementMessageIfReachable()
            }
        }
    }

    /// Updates pairing and install state when watch state changes.
    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        print(
            "[WatchConnectivityManager] Session state changed: isPaired(\(isPaired)), isWatchAppInstalled(\(isWatchAppInstalled))"
        )
        Task { @MainActor [weak self] in
            guard let self else { return }
            // Pairing remains true while the watch is off-wrist; installation is tracked separately.
            self.isPaired = isPaired
            self.isWatchAppInstalled = isWatchAppInstalled
            if isPaired, isWatchAppInstalled, hasPendingEntitlementTransfer {
                syncCurrentEntitlementToWatch(transferDurably: true)
            }
        }
    }

    /// Logs when the current session becomes inactive.
    nonisolated func sessionDidBecomeInactive(_: WCSession) {
        print("[WatchConnectivityManager] Session did become inactive")
    }

    /// Reactivates the session after deactivation.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivityManager] Session did deactivate")
        session.activate()
    }

    /// Logs incoming direct messages from the watch app.
    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchConnectivityManager] Received message: \(message)")
        if let data = message["workoutEvent"] as? Data {
            Task { @MainActor [weak self] in
                do {
                    let payload = try JSONDecoder().decode(MirroredWorkoutPayload.self, from: data)
                    self?.onWorkoutEventReceived?(payload)
                } catch {
                    print("[WatchConnectivityManager] Failed to decode workout event: \(error)")
                }
            }
        }
        if message["watch app"] as? String == "startCancelled" {
            Task { @MainActor [weak self] in
                self?.onWorkoutStartCancelled?()
            }
        }
    }

    /// Responds to synchronous Watch requests for the latest entitlement and quota state.
    nonisolated func session(
        _: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        print("[WatchConnectivityManager] Received message with reply: \(message)")
        if message["action"] as? String == "requestEntitlement" {
            let store = NSUbiquitousKeyValueStore.default
            store.synchronize()
            replyHandler([
                "type": "entitlementState",
                "hasUnlockedUnlimitedWorkouts": store.bool(forKey: "hasUnlockedUnlimitedWorkouts"),
                "qualifiedWorkoutCount": Int(store.longLong(forKey: "qualifiedWorkoutCount")),
                "updatedAt": Date().timeIntervalSince1970,
            ])
            return
        }
        replyHandler([:])
    }

    /// Applies settings synced via application context.
    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        guard let type = applicationContext["type"] as? String, type == "goalSettings" else {
            return
        }
        guard let goalTypeRawValue = applicationContext["goalType"] as? String,
              let jumpCount = NumberParser.int(applicationContext["jumpCount"]),
              let jumpTime = NumberParser.int(applicationContext["jumpTime"])
        else {
            print("[WatchConnectivityManager] Invalid goal settings payload")
            return
        }

        let shouldSpeakJumpCountAnnouncements = applicationContext["shouldSpeakJumpCountAnnouncements"] as? Bool ?? true
        let shouldSpeakJumpTimeAnnouncements = applicationContext["shouldSpeakJumpTimeAnnouncements"] as? Bool ?? true
        let jumpDetectorThresholdAdjustmentPercentage = NumberParser.double(applicationContext["jumpDetectorThresholdAdjustmentPercentage"])
            ?? 0.0

        Task { @MainActor [weak self] in
            self?.applySettings(
                goalTypeRawValue: goalTypeRawValue,
                jumpCount: jumpCount,
                jumpTime: jumpTime,
                shouldSpeakJumpCountAnnouncements: shouldSpeakJumpCountAnnouncements,
                shouldSpeakJumpTimeAnnouncements: shouldSpeakJumpTimeAnnouncements,
                jumpDetectorThresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage
            )
        }
    }

    /// Handles incoming files transferred from the watch app.
    nonisolated func session(_: WCSession, didReceive file: WCSessionFile) {
        #if DEBUG
            let filename = (file.metadata?["filename"] as? String) ?? file.fileURL.lastPathComponent
            let startedAt = NumberParser.double(file.metadata?["startedAt"]).map(Date.init(timeIntervalSince1970:))
            print("[WatchConnectivityManager] Received file from watch: \(filename)")
            do {
                // Copy the temporary file during the callback; WatchConnectivity owns its lifetime.
                let data = try Data(contentsOf: file.fileURL)
                if let csvText = String(data: data, encoding: .utf8) {
                    Task { @MainActor [weak self] in
                        await self?.handleReceivedMotionCSV(csvText: csvText, filename: filename, startedAt: startedAt)
                    }
                } else {
                    print("[WatchConnectivityManager] Failed to decode CSV file content")
                }
            } catch {
                print("[WatchConnectivityManager] Error reading received file: \(error.localizedDescription)")
            }
        #endif
    }

    /// Handles user-info transfers for sessions and CSV fallbacks.
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WatchConnectivityManager] Received userInfo: \(userInfo)")

        if let type = userInfo["type"] as? String, type == "sessionComplete" {
            handleCompletedSessionPayload(userInfo)
            return
        }

        #if DEBUG
            guard let csvText = userInfo["csvText"] as? String,
                  let filename = userInfo["filename"] as? String
            else {
                print("[WatchConnectivityManager] userInfo missing csvText or filename")
                return
            }
            let startedAt = NumberParser.double(userInfo["startedAt"]).map(Date.init(timeIntervalSince1970:))
            Task { @MainActor [weak self] in
                await self?.handleReceivedMotionCSV(csvText: csvText, filename: filename, startedAt: startedAt)
            }
        #endif
    }

    /// Parses a loosely typed completed-session payload on the delegate callback thread.
    private nonisolated func handleCompletedSessionPayload(_ userInfo: [String: Any]) {
        guard let startedAtTimestamp = NumberParser.double(userInfo["startedAt"]),
              let endedAtTimestamp = NumberParser.double(userInfo["endedAt"]),
              let jumpCount = NumberParser.int(userInfo["jumpCount"]),
              let caloriesBurned = NumberParser.double(userInfo["caloriesBurned"]),
              let jumpOffsets = (userInfo["jumpOffsets"] as? [Any])?.compactMap(NumberParser.double)
        else {
            print("[WatchConnectivityManager] Invalid completed session payload")
            return
        }

        let startedAt = Date(timeIntervalSince1970: startedAtTimestamp)
        let endedAt = Date(timeIntervalSince1970: endedAtTimestamp)
        let doubleUndersCount = NumberParser.int(userInfo["doubleUndersCount"])
            ?? SessionMetricsCalculator.doubleUndersCount(from: jumpOffsets)
        let averageHeartRate = NumberParser.int(userInfo["averageHeartRate"])
        let peakHeartRate = NumberParser.int(userInfo["peakHeartRate"])
        let goalType = (userInfo["goalType"] as? String).flatMap(GoalType.init(rawValue:))

        Task { @MainActor [weak self] in
            self?.saveCompletedSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                doubleUndersCount: doubleUndersCount,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate,
                goalType: goalType
            )
        }
    }

    /// Persists a parsed watch session and notifies the main-actor app state.
    private func saveCompletedSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        doubleUndersCount: Int,
        averageHeartRate: Int?,
        peakHeartRate: Int?,
        goalType: GoalType?
    ) {
        let savedSession = MyDataStore.shared.saveCompletedSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpCount,
            caloriesBurned: caloriesBurned,
            jumpOffsets: jumpOffsets,
            doubleUndersCount: doubleUndersCount,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRate,
            goalType: goalType
        )

        onCompletedSessionReceived?(
            startedAt,
            endedAt,
            jumpCount,
            caloriesBurned,
            jumpOffsets,
            averageHeartRate,
            peakHeartRate,
            savedSession.session,
            savedSession.achievedRecordKinds
        )
        print("[WatchConnectivityManager] Saved completed session from watch: \(jumpCount) jumps")
    }

    /// Syncs the selected workout settings, quota, and license state to Apple Watch.
    func syncSettings(
        goalType: GoalType,
        jumpCount: Int64,
        jumpTime: Int64,
        shouldSpeakJumpCountAnnouncements: Bool,
        shouldSpeakJumpTimeAnnouncements: Bool,
        jumpDetectorThresholdAdjustmentPercentage: Double,
        hasUnlockedUnlimitedWorkouts: Bool? = nil,
        qualifiedWorkoutCount: Int? = nil
    ) {
        guard isSupported, session.activationState == .activated else { return }

        settingsStore.synchronize()
        let resolvedUnlimited = hasUnlockedUnlimitedWorkouts ?? PurchaseManager.shared.hasUnlockedUnlimitedWorkouts
        let resolvedQualifiedCount = qualifiedWorkoutCount ?? Int(settingsStore.longLong(forKey: "qualifiedWorkoutCount"))

        let payload: [String: Any] = [
            "type": "goalSettings",
            "accentColor": AppAppearance.shared.accent.rawValue,
            "goalType": goalType.rawValue,
            "jumpCount": jumpCount,
            "jumpTime": jumpTime,
            "shouldSpeakJumpCountAnnouncements": shouldSpeakJumpCountAnnouncements,
            "shouldSpeakJumpTimeAnnouncements": shouldSpeakJumpTimeAnnouncements,
            "jumpDetectorThresholdAdjustmentPercentage": jumpDetectorThresholdAdjustmentPercentage,
            "hasUnlockedUnlimitedWorkouts": resolvedUnlimited,
            "qualifiedWorkoutCount": resolvedQualifiedCount,
            "updatedAt": Date().timeIntervalSince1970,
        ]

        do {
            try session.updateApplicationContext(payload)
            print("[WatchConnectivityManager] Updated application context with goal settings")
        } catch {
            print("[WatchConnectivityManager] Failed to update goal settings application context: \(error.localizedDescription)")
        }

        guard session.isReachable else { return }
        // Application context queues the latest settings; reachable messages apply them immediately.
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send immediate goal settings message: \(error.localizedDescription)")
        }
    }

    /// Pushes the latest entitlement state to Watch via application context, durable transfer, and live message.
    func syncCurrentEntitlementToWatch(transferDurably: Bool) {
        guard isSupported else { return }
        guard session.activationState == .activated else {
            if transferDurably {
                hasPendingEntitlementTransfer = true
            }
            return
        }

        settingsStore.synchronize()
        let hasUnlockedUnlimitedWorkouts = PurchaseManager.shared.hasUnlockedUnlimitedWorkouts
        let qualifiedWorkoutCount = Int(settingsStore.longLong(forKey: "qualifiedWorkoutCount"))
        let updatedAt = Date().timeIntervalSince1970

        let entitlementPayload = makeEntitlementPayload(
            hasUnlockedUnlimitedWorkouts: hasUnlockedUnlimitedWorkouts,
            qualifiedWorkoutCount: qualifiedWorkoutCount,
            updatedAt: updatedAt
        )
        let contextPayload = currentGoalSettingsPayload(
            hasUnlockedUnlimitedWorkouts: hasUnlockedUnlimitedWorkouts,
            qualifiedWorkoutCount: qualifiedWorkoutCount,
            updatedAt: updatedAt
        )

        do {
            try session.updateApplicationContext(contextPayload)
            print("[WatchConnectivityManager] Updated application context with entitlement state")
        } catch {
            print("[WatchConnectivityManager] Failed to update entitlement application context: \(error.localizedDescription)")
        }

        if transferDurably {
            if session.isPaired, session.isWatchAppInstalled {
                session.transferUserInfo(entitlementPayload)
                hasPendingEntitlementTransfer = false
                print("[WatchConnectivityManager] Queued entitlement state via transferUserInfo")
            } else if session.isPaired {
                // Keep pending until the Watch app install state settles after activation.
                hasPendingEntitlementTransfer = true
            } else {
                hasPendingEntitlementTransfer = false
            }
        }

        guard session.isReachable else { return }
        session.sendMessage(entitlementPayload, replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send immediate entitlement message: \(error.localizedDescription)")
        }
    }

    /// Sends a lightweight entitlement snapshot when Watch becomes reachable.
    private func sendCurrentEntitlementMessageIfReachable() {
        guard isSupported, session.activationState == .activated, session.isReachable else { return }

        settingsStore.synchronize()
        let payload = makeEntitlementPayload(
            hasUnlockedUnlimitedWorkouts: PurchaseManager.shared.hasUnlockedUnlimitedWorkouts,
            qualifiedWorkoutCount: Int(settingsStore.longLong(forKey: "qualifiedWorkoutCount")),
            updatedAt: Date().timeIntervalSince1970
        )
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send entitlement message on reachability: \(error.localizedDescription)")
        }
    }

    private func makeEntitlementPayload(
        hasUnlockedUnlimitedWorkouts: Bool,
        qualifiedWorkoutCount: Int,
        updatedAt: TimeInterval
    ) -> [String: Any] {
        [
            "type": "entitlementState",
            "hasUnlockedUnlimitedWorkouts": hasUnlockedUnlimitedWorkouts,
            "qualifiedWorkoutCount": qualifiedWorkoutCount,
            "updatedAt": updatedAt,
        ]
    }

    private func currentGoalSettingsPayload(
        hasUnlockedUnlimitedWorkouts: Bool,
        qualifiedWorkoutCount: Int,
        updatedAt: TimeInterval
    ) -> [String: Any] {
        let storedGoalType: GoalType = settingsStore.string(forKey: "goalType") == GoalType.time.rawValue ? .time : .count
        let storedJumpCount = settingsStore.longLong(forKey: "jumpCount")
        let storedJumpTime = settingsStore.longLong(forKey: "jumpTime")
        let shouldSpeakJumpCountAnnouncements = settingsStore.object(forKey: "shouldSpeakJumpCountAnnouncements") as? Bool ?? true
        let shouldSpeakJumpTimeAnnouncements = settingsStore.object(forKey: "shouldSpeakJumpTimeAnnouncements") as? Bool ?? true
        let storedThresholdAdjustment = (settingsStore.object(forKey: "jumpDetectorThresholdAdjustmentPercentage") as? NSNumber)?.doubleValue
            ?? DefaultJumpDetectorThresholdAdjustmentPercentage

        return [
            "type": "goalSettings",
            "accentColor": AppAppearance.shared.accent.rawValue,
            "goalType": storedGoalType.rawValue,
            "jumpCount": storedJumpCount == 0 ? DefaultJumpCount : storedJumpCount,
            "jumpTime": storedJumpTime == 0 ? DefaultJumpTime : storedJumpTime,
            "shouldSpeakJumpCountAnnouncements": shouldSpeakJumpCountAnnouncements,
            "shouldSpeakJumpTimeAnnouncements": shouldSpeakJumpTimeAnnouncements,
            "jumpDetectorThresholdAdjustmentPercentage": JumpRecSettings.clampedJumpDetectorThresholdAdjustmentPercentage(
                storedThresholdAdjustment
            ),
            "hasUnlockedUnlimitedWorkouts": hasUnlockedUnlimitedWorkouts,
            "qualifiedWorkoutCount": qualifiedWorkoutCount,
            "updatedAt": updatedAt,
        ]
    }

    /// Asks the already-running Watch app to start a companion workout when HealthKit skips re-delivery.
    func sendStartSessionCommand() {
        guard session.isReachable else {
            print("[WatchConnectivityManager] Watch is not reachable for fallback start command")
            return
        }
        session.sendMessage(["action": "startWorkout"], replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send start workout message: \(error.localizedDescription)")
        }
    }

    /// Cancels a pending companion-triggered countdown on Watch when iPhone cancels starting.
    func sendCancelStartCommand() {
        guard session.isReachable else { return }
        session.sendMessage(["action": "cancelStart"], replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send cancel start message: \(error.localizedDescription)")
        }
    }

    /// Requests Watch to end the mirrored workout and return its final metrics.
    func sendStopSessionCommand(onDeliveryFailure: @escaping @MainActor @Sendable () -> Void) {
        guard session.isReachable else {
            print("[WatchConnectivityManager] Watch is not reachable to receive stop command")
            onDeliveryFailure()
            return
        }
        let payload: [String: Any] = ["action": "stopWorkout"]
        session.sendMessage(payload, replyHandler: nil) { error in
            print("[WatchConnectivityManager] Failed to send stop workout message: \(error.localizedDescription)")
            Task { @MainActor in
                onDeliveryFailure()
            }
        }
    }

    /// Persists a parsed goal-settings payload and notifies main-actor observers.
    private func applySettings(
        goalTypeRawValue: String,
        jumpCount: Int,
        jumpTime: Int,
        shouldSpeakJumpCountAnnouncements: Bool,
        shouldSpeakJumpTimeAnnouncements: Bool,
        jumpDetectorThresholdAdjustmentPercentage: Double
    ) {
        settingsStore.set(goalTypeRawValue, forKey: "goalType")
        settingsStore.set(Int64(jumpCount), forKey: "jumpCount")
        settingsStore.set(Int64(jumpTime), forKey: "jumpTime")
        settingsStore.set(shouldSpeakJumpCountAnnouncements, forKey: "shouldSpeakJumpCountAnnouncements")
        settingsStore.set(shouldSpeakJumpTimeAnnouncements, forKey: "shouldSpeakJumpTimeAnnouncements")
        settingsStore.set(
            JumpRecSettings.clampedJumpDetectorThresholdAdjustmentPercentage(jumpDetectorThresholdAdjustmentPercentage),
            forKey: "jumpDetectorThresholdAdjustmentPercentage"
        )
        settingsStore.synchronize()

        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }

    #if DEBUG
        /// Saves a received motion CSV locally, notifies active UI observers, and exports to iCloud.
        private func handleReceivedMotionCSV(csvText: String, filename: String, startedAt: Date?) async {
            if let fileURL = saveCSVToLocalDocuments(csvText: csvText, filename: filename) {
                onMotionCSVReceived?(fileURL, startedAt)
            }
            await saveCSVToICloud(csvText: csvText, filename: filename)
        }
    #endif

    /// Exports CSV to iCloud Documents, waiting asynchronously for the container.
    func saveCSVToICloud(
        csvText: String,
        filename: String,
        containerIdentifier: String = "iCloud.com.kinn.JumpRec"
    ) async {
        #if DEBUG
            await cloudCSVExporter.save(
                csvText: csvText,
                filename: filename,
                containerIdentifier: containerIdentifier
            )
        #endif
    }

    /// Saves CSV text to the app's local Documents directory.
    @discardableResult
    func saveCSVToLocalDocuments(csvText: String, filename: String) -> URL? {
        #if DEBUG
            return DebugMotionCSVStore.shared.save(csvText: csvText, filename: filename)
        #else
            return nil
        #endif
    }
}
