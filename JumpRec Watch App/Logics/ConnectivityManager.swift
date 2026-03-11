//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation
import JumpRecShared
import WatchConnectivity

final class ConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = ConnectivityManager()

    private let session: WCSession = .default
    private let settingsStore = NSUbiquitousKeyValueStore.default

    override private init() {
        super.init()
        if WCSession.isSupported() {
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - WCSessionDelegate

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

    func sendMessage(_ message: [String: Any]) {
        guard session.isReachable else {
            print("[WatchConnectivityManager] Session not reachable or not paired")
            return
        }
        session.sendMessage(message, replyHandler: nil, errorHandler: { error in
            print("[WatchConnectivityManager] Failed to send message with error: \(error.localizedDescription)")
        })
    }

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

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
    }

    func session(_: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        print("[WatchConnectivityManager] Received application context: \(applicationContext)")
        applySettingsPayload(applicationContext)
    }

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
