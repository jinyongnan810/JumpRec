//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation
import WatchConnectivity

final class ConnectivityManager: NSObject, WCSessionDelegate {
    /// Shared singleton used by the watch app.
    static let shared = ConnectivityManager()

    /// The active WatchConnectivity session.
    private let session: WCSession = .default
    /// Persists synced settings received from the phone.
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

    /// Handles activation completion and applies any queued settings payload.
    func session(_: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if let error {
            print("[WatchConnectivityManager] Activation failed with error: \(error.localizedDescription)")
        } else {
            print("[WatchConnectivityManager] Activation completed with state: \(activationState.rawValue)")
        }

        applySettingsPayload(session.receivedApplicationContext)
    }

    /// Sends CSV text to iPhone via transferFile. Falls back to transferUserInfo if file creation fails.
    /// - Parameters:
    ///   - csvText: The CSV content as string
    ///   - filename: The filename for the CSV file
    /// Transfers a CSV export to the iPhone companion app.
    func sendCSV(_ csvText: String, filename: String) {
        guard session.isReachable else {
            print("[WatchConnectivityManager] Session not reachable or not paired")
            return
        }
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try csvText.write(to: tempURL, atomically: true, encoding: .utf8)
            session.transferFile(tempURL, metadata: ["filename": filename])
            print("[WatchConnectivityManager] Sent CSV file via transferFile: \(filename)")
        } catch {
            print("[WatchConnectivityManager] Failed to write temp CSV file: \(error.localizedDescription). Falling back to transferUserInfo.")
            session.transferUserInfo(["csvText": csvText, "filename": filename])
        }
    }

    /// Sends a reachable message directly to the iPhone app.
    func sendMessage(_ message: [String: Any]) {
        guard session.isReachable else {
            print("[WatchConnectivityManager] Session not reachable or not paired")
            return
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("[WatchConnectivityManager] Failed to send message with error: \(error.localizedDescription)")
        })
    }

    /// Queues a completed workout payload for delivery to the iPhone app.
    func sendCompletedSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int?,
        peakHeartRate: Int?
    ) {
        var payload: [String: Any] = [
            "type": "sessionComplete",
            "startedAt": startedAt.timeIntervalSince1970,
            "endedAt": endedAt.timeIntervalSince1970,
            "jumpCount": jumpCount,
            "caloriesBurned": caloriesBurned,
            "jumpOffsets": jumpOffsets,
        ]
        payload["averageHeartRate"] = averageHeartRate
        payload["peakHeartRate"] = peakHeartRate
        session.transferUserInfo(payload)
        print("[WatchConnectivityManager] Queued completed session via transferUserInfo")
    }

    /// Logs changes to reachability with the iPhone app.
    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
    }

    /// Applies updated goal settings received from the iPhone app.
    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        applySettingsPayload(applicationContext)
    }

    /// Validates and persists a settings payload from the iPhone app.
    private func applySettingsPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String, type == "goalSettings" else {
            return
        }

        guard let goalTypeRawValue = payload["goalType"] as? String,
              let jumpCount = payload["jumpCount"] as? Int,
              let jumpTime = payload["jumpTime"] as? Int
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
}
