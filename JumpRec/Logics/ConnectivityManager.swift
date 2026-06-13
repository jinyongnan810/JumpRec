//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
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
    var onCompletedSessionReceived: ((Date, Date, Int, Double, [TimeInterval], Int?, Int?, JumpSession) -> Void)?
    /// ⭐️Persists synced settings in the shared ubiquitous key-value store.
    private let settingsStore = NSUbiquitousKeyValueStore.default
    /// Performs potentially delayed iCloud container resolution and file writes away from UI state.
    private let cloudCSVExporter = CloudCSVExporter()

    /// Configures and activates the shared connectivity session.
    override private init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
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

        // WCSession properties are read on the delegate callback thread, then only
        // Sendable value snapshots cross to the main actor for observable state updates.
        let isPaired = session.isPaired
        let isWatchAppInstalled = session.isWatchAppInstalled
        let isReachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.activationState = activationState
            self?.isPaired = isPaired
            self?.isWatchAppInstalled = isWatchAppInstalled
            self?.isReachable = isReachable
        }
    }

    /// Updates reachability when the watch app becomes reachable or unreachable.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("[WatchConnectivityManager] Session reachability changed: \(isReachable)")
        Task { @MainActor [weak self] in
            self?.isReachable = isReachable
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
            // Pairing remains true while the watch is off-wrist; installation is tracked separately.
            self?.isPaired = isPaired
            self?.isWatchAppInstalled = isWatchAppInstalled
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

        Task { @MainActor [weak self] in
            self?.applySettings(
                goalTypeRawValue: goalTypeRawValue,
                jumpCount: jumpCount,
                jumpTime: jumpTime
            )
        }
    }

    /// Handles incoming files transferred from the watch app.
    nonisolated func session(_: WCSession, didReceive file: WCSessionFile) {
        let filename = file.fileURL.lastPathComponent
        print("[WatchConnectivityManager] Received file from watch: \(filename)")
        do {
            // WatchConnectivity owns this temporary URL only for the callback lifetime,
            // so copy its contents before starting any asynchronous work.
            let data = try Data(contentsOf: file.fileURL)
            if let csvText = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    await self?.saveCSVToICloud(csvText: csvText, filename: filename)
                }
            } else {
                print("[WatchConnectivityManager] Failed to decode CSV file content")
            }
        } catch {
            print("[WatchConnectivityManager] Error reading received file: \(error.localizedDescription)")
        }
    }

    /// Handles user-info transfers for sessions and CSV fallbacks.
    nonisolated func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WatchConnectivityManager] Received userInfo: \(userInfo)")

        if let type = userInfo["type"] as? String, type == "sessionComplete" {
            handleCompletedSessionPayload(userInfo)
            return
        }

        guard let csvText = userInfo["csvText"] as? String,
              let filename = userInfo["filename"] as? String
        else {
            print("[WatchConnectivityManager] userInfo missing csvText or filename")
            return
        }
        Task { @MainActor [weak self] in
            await self?.saveCSVToICloud(csvText: csvText, filename: filename)
        }
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
        let averageHeartRate = NumberParser.int(userInfo["averageHeartRate"])
        let peakHeartRate = NumberParser.int(userInfo["peakHeartRate"])

        Task { @MainActor [weak self] in
            self?.saveCompletedSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
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
        averageHeartRate: Int?,
        peakHeartRate: Int?
    ) {
        let session = MyDataStore.shared.saveCompletedSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpCount,
            caloriesBurned: caloriesBurned,
            jumpOffsets: jumpOffsets,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRate
        )

        onCompletedSessionReceived?(
            startedAt,
            endedAt,
            jumpCount,
            caloriesBurned,
            jumpOffsets,
            averageHeartRate,
            peakHeartRate,
            session
        )
        print("[WatchConnectivityManager] Saved completed session from watch: \(jumpCount) jumps")
    }

    /// Syncs the selected workout settings to Apple Watch.
    func syncSettings(goalType: GoalType, jumpCount: Int64, jumpTime: Int64) {
        let payload: [String: Any] = [
            "type": "goalSettings",
            "goalType": goalType.rawValue,
            "jumpCount": jumpCount,
            "jumpTime": jumpTime,
        ]

        do {
            try session.updateApplicationContext(payload)
            print("[WatchConnectivityManager] Updated application context with goal settings")
        } catch {
            print("[WatchConnectivityManager] Failed to update goal settings application context: \(error.localizedDescription)")
        }
    }

    /// Persists a parsed goal-settings payload and notifies main-actor observers.
    private func applySettings(goalTypeRawValue: String, jumpCount: Int, jumpTime: Int) {
        settingsStore.set(goalTypeRawValue, forKey: "goalType")
        settingsStore.set(Int64(jumpCount), forKey: "jumpCount")
        settingsStore.set(Int64(jumpTime), forKey: "jumpTime")
        settingsStore.synchronize()

        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }

    /// Saves CSV text to iCloud Drive without blocking the caller while iCloud becomes available.
    /// - Parameters:
    ///   - csvText: The CSV content as a string.
    ///   - filename: The destination filename in the iCloud Documents directory.
    ///   - containerIdentifier: The iCloud container identifier used for the export.
    func saveCSVToICloud(
        csvText: String,
        filename: String,
        containerIdentifier: String = "iCloud.com.kinn.JumpRec"
    ) async {
        await cloudCSVExporter.save(
            csvText: csvText,
            filename: filename,
            containerIdentifier: containerIdentifier
        )
    }

    /// Saves CSV text to the app's local Documents directory.
    /// - Parameters:
    ///   - csvText: The CSV content as string
    ///   - filename: The filename for the CSV file
    @discardableResult
    func saveCSVToLocalDocuments(csvText: String, filename: String) -> URL? {
        do {
            let documentsURL = try FileManager.default.url(
                for: .documentDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let fileURL = documentsURL.appendingPathComponent(filename)
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[WatchConnectivityManager] Saved CSV to local Documents at \(fileURL.path)")
            return fileURL
        } catch {
            print("[WatchConnectivityManager] Error saving CSV to local Documents: \(error.localizedDescription)")
            return nil
        }
    }
}
