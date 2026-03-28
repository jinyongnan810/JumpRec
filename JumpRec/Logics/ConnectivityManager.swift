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
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchConnectivityManager] Activation failed with error: \(error.localizedDescription)")
        } else {
            print("[WatchConnectivityManager] Activation completed with state: \(activationState.rawValue)")
        }
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.isReachable = session.isReachable
        }
    }

    /// Updates reachability when the watch app becomes reachable or unreachable.
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    /// Updates pairing and install state when watch state changes.
    func sessionWatchStateDidChange(_ session: WCSession) {
        print(
            "[WatchConnectivityManager] Session state changed: isPaired(\(session.isPaired)), isWatchAppInstalled(\(session.isWatchAppInstalled))"
        )
        DispatchQueue.main.async {
            // isPaired is true even the watch is took off
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    /// Logs when the current session becomes inactive.
    func sessionDidBecomeInactive(_: WCSession) {
        print("[WatchConnectivityManager] Session did become inactive")
    }

    /// Reactivates the session after deactivation.
    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivityManager] Session did deactivate")
        session.activate()
    }

    /// Logs incoming direct messages from the watch app.
    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchConnectivityManager] Received message: \(message)")
    }

    /// Applies settings synced via application context.
    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        applySettingsPayload(applicationContext)
    }

    /// Handles incoming files transferred from the watch app.
    func session(_: WCSession, didReceive file: WCSessionFile) {
        print("[WatchConnectivityManager] Received file from watch: \(file.fileURL.lastPathComponent)")
        do {
            let data = try Data(contentsOf: file.fileURL)
            if let csvText = String(data: data, encoding: .utf8) {
                saveCSVtoICloud(csvText: csvText, filename: file.fileURL.lastPathComponent)
            } else {
                print("[WatchConnectivityManager] Failed to decode CSV file content")
            }
        } catch {
            print("[WatchConnectivityManager] Error reading received file: \(error.localizedDescription)")
        }
    }

    /// Handles user-info transfers for sessions and CSV fallbacks.
    func session(_: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        print("[WatchConnectivityManager] Received userInfo: \(userInfo)")

        if let type = userInfo["type"] as? String, type == "sessionComplete" {
            handleCompletedSession(userInfo)
            return
        }

        guard let csvText = userInfo["csvText"] as? String,
              let filename = userInfo["filename"] as? String
        else {
            print("[WatchConnectivityManager] userInfo missing csvText or filename")
            return
        }
        saveCSVtoICloud(csvText: csvText, filename: filename)
    }

    /// Rebuilds and persists a completed session received from Apple Watch.
    private func handleCompletedSession(_ userInfo: [String: Any]) {
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

        Task { @MainActor in
            let session = MyDataStore.shared.saveCompletedSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )

            self.onCompletedSessionReceived?(
                startedAt,
                endedAt,
                jumpCount,
                caloriesBurned,
                jumpOffsets,
                averageHeartRate,
                peakHeartRate,
                session
            )
        }

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

    /// Validates and applies a goal-settings payload from the watch session.
    private func applySettingsPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String, type == "goalSettings" else {
            return
        }

        guard let goalTypeRawValue = payload["goalType"] as? String,
              let jumpCount = NumberParser.int(payload["jumpCount"]),
              let jumpTime = NumberParser.int(payload["jumpTime"])
        else {
            print("[WatchConnectivityManager] Invalid goal settings payload")
            return
        }

        settingsStore.set(goalTypeRawValue, forKey: "goalType")
        settingsStore.set(Int64(jumpCount), forKey: "jumpCount")
        settingsStore.set(Int64(jumpTime), forKey: "jumpTime")
        settingsStore.synchronize()

        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }

    /// Saves CSV text to iCloud Drive in the specified container
    /// - Parameters:
    ///   - csvText: The CSV content as string
    ///   - filename: The filename for the CSV file
    ///   - containerId: The iCloud container identifier (default: "iCloud.com.kinn.JumpRec")
    func saveCSVtoICloud(csvText: String, filename: String, containerId: String = "iCloud.com.kinn.JumpRec") {
        // Check ubiquityIdentityToken, retry if needed
        var ubiquityToken = FileManager.default.ubiquityIdentityToken
        var containerURL: URL? = nil
        var attempt = 0

        while ubiquityToken == nil, attempt < 5 {
            print("[WatchConnectivityManager] Waiting for iCloud ubiquityIdentityToken...")
            Thread.sleep(forTimeInterval: 0.5)
            ubiquityToken = FileManager.default.ubiquityIdentityToken
            attempt += 1
        }

        guard ubiquityToken != nil else {
            print("[WatchConnectivityManager] iCloud not available or user not logged in")
            return
        }

        containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)

        attempt = 0
        while containerURL == nil, attempt < 5 {
            print("[WatchConnectivityManager] Waiting for iCloud container URL...")
            Thread.sleep(forTimeInterval: 0.5)
            containerURL = FileManager.default.url(forUbiquityContainerIdentifier: containerId)
            attempt += 1
        }

        guard let container = containerURL else {
            print("[WatchConnectivityManager] Could not resolve iCloud container URL")
            return
        }

        let documentsURL = container.appendingPathComponent("Documents", isDirectory: true)

        do {
            if !FileManager.default.fileExists(atPath: documentsURL.path) {
                try FileManager.default.createDirectory(at: documentsURL, withIntermediateDirectories: true, attributes: nil)
                print("[WatchConnectivityManager] Created Documents directory in iCloud container")
            }

            let fileURL = documentsURL.appendingPathComponent(filename)
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            print("[WatchConnectivityManager] Saved CSV to iCloud at \(fileURL.path)")
        } catch {
            print("[WatchConnectivityManager] Error saving CSV to iCloud: \(error.localizedDescription)")
        }
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
