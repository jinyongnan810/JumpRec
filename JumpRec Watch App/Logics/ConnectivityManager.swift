//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/23.
//

import Foundation
import WatchConnectivity

final class ConnectivityManager: NSObject, WCSessionDelegate {
    static let shared = ConnectivityManager()

    private let session: WCSession = .default

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

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
    }
}
