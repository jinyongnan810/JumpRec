//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation
import JumpRecShared
import SwiftData
import WatchConnectivity

@Observable
final class ConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = ConnectivityManager()

    private let session: WCSession = .default

    var isSupported: Bool = WCSession.isSupported()
    var isPaired: Bool = false
    var isWatchAppInstalled: Bool = false
    var isReachable: Bool = false
    var activationState: WCSessionActivationState = .notActivated
    var onCompletedSessionReceived: ((Date, Date, Int, Double, [TimeInterval], Int?, Int?) -> Void)?
    private let settingsStore = NSUbiquitousKeyValueStore.default

    override private init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - WCSessionDelegate

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

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        print(
            "[WatchConnectivityManager] Session state changed: isPaired(\(session.isPaired)), isWatchAppInstalled(\(session.isWatchAppInstalled))"
        )
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    func sessionDidBecomeInactive(_: WCSession) {
        print("[WatchConnectivityManager] Session did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivityManager] Session did deactivate")
        session.activate()
    }

    func session(
        _: WCSession,
        didReceiveMessage message: [String: Any]
    ) {
        print("[WatchConnectivityManager] Received message: \(message)")
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        applySettingsPayload(applicationContext)
    }

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

    private func handleCompletedSession(_ userInfo: [String: Any]) {
        guard let startedAtTimestamp = numberAsDouble(userInfo["startedAt"]),
              let endedAtTimestamp = numberAsDouble(userInfo["endedAt"]),
              let jumpCount = numberAsInt(userInfo["jumpCount"]),
              let caloriesBurned = numberAsDouble(userInfo["caloriesBurned"]),
              let jumpOffsets = (userInfo["jumpOffsets"] as? [Any])?.compactMap(numberAsDouble)
        else {
            print("[WatchConnectivityManager] Invalid completed session payload")
            return
        }

        let startedAt = Date(timeIntervalSince1970: startedAtTimestamp)
        let endedAt = Date(timeIntervalSince1970: endedAtTimestamp)
        let averageHeartRate = numberAsInt(userInfo["averageHeartRate"])
        let peakHeartRate = numberAsInt(userInfo["peakHeartRate"])

        Task { @MainActor in
            self.onCompletedSessionReceived?(
                startedAt,
                endedAt,
                jumpCount,
                caloriesBurned,
                jumpOffsets,
                averageHeartRate,
                peakHeartRate
            )

            MyDataStore.shared.saveCompletedSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )
        }

        print("[WatchConnectivityManager] Saved completed session from watch: \(jumpCount) jumps")
    }

    private func numberAsDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func numberAsInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }

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

    private func applySettingsPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String, type == "goalSettings" else {
            return
        }

        guard let goalTypeRawValue = payload["goalType"] as? String,
              let jumpCount = numberAsInt(payload["jumpCount"]),
              let jumpTime = numberAsInt(payload["jumpTime"])
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
}
