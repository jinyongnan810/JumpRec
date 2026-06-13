//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation
import WatchConnectivity

@MainActor
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

        parseSettingsPayload(session.receivedApplicationContext)
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
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
    }

    /// Applies updated goal settings received from the iPhone app.
    nonisolated func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        parseSettingsPayload(applicationContext)
    }

    /// Parses loosely typed settings on the WatchConnectivity callback thread.
    private nonisolated func parseSettingsPayload(_ payload: [String: Any]) {
        guard let type = payload["type"] as? String, type == "goalSettings" else {
            return
        }

        guard let goalTypeRawValue = payload["goalType"] as? String,
              let jumpCount = (payload["jumpCount"] as? NSNumber)?.intValue,
              let jumpTime = (payload["jumpTime"] as? NSNumber)?.intValue
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

    /// Persists parsed settings and notifies main-actor observers.
    private func applySettings(goalTypeRawValue: String, jumpCount: Int, jumpTime: Int) {
        settingsStore.set(goalTypeRawValue, forKey: "goalType")
        settingsStore.set(Int64(jumpCount), forKey: "jumpCount")
        settingsStore.set(Int64(jumpTime), forKey: "jumpTime")
        settingsStore.synchronize()

        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }
}
