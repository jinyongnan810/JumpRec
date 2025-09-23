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

    func sessionDidBecomeInactive(_: WCSession) {
        print("[WatchConnectivityManager] Session did become inactive")
    }

    func sessionDidDeactivate(_ session: WCSession) {
        print("[WatchConnectivityManager] Session did deactivate")
        session.activate()
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
        guard let csvText = userInfo["csvText"] as? String,
              let filename = userInfo["filename"] as? String
        else {
            print("[WatchConnectivityManager] userInfo missing csvText or filename")
            return
        }
        saveCSVtoICloud(csvText: csvText, filename: filename)
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        print("[WatchConnectivityManager] Session reachability changed: \(session.isReachable)")
    }
}
