//
//  ConnectivityManager.swift
//  JumpRec
//
//  Created by kinn on 2025/09/23.
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

        #if DEBUG
            if activationState == .activated {
                Task { @MainActor [weak self] in
                    self?.flushPendingMotionCSVs()
                }
            }
        #endif
    }

    #if DEBUG
        /// Returns the number of debug motion CSV files still waiting to finish transferring to iPhone.
        var pendingMotionCSVCount: Int {
            pendingMotionCSVURLs().count
        }

        /// Queues a debug motion CSV for background-durable transfer to iPhone without requiring live reachability.
        func sendMotionCSV(_ csvText: String, filename: String, startedAt: Date) {
            guard WCSession.isSupported() else { return }

            do {
                let fileURL = try writePendingMotionCSV(csvText: csvText, filename: filename)
                guard session.activationState == .activated else {
                    print("[WatchConnectivityManager] Queued motion CSV until WCSession activates: \(filename)")
                    return
                }
                session.transferFile(
                    fileURL,
                    metadata: [
                        "filename": filename,
                        "startedAt": startedAt.timeIntervalSince1970,
                    ]
                )
                print("[WatchConnectivityManager] Queued motion CSV via transferFile: \(filename)")
            } catch {
                print("[WatchConnectivityManager] Failed to write pending CSV file: \(error.localizedDescription). Falling back to transferUserInfo.")
                guard session.activationState == .activated else { return }
                session.transferUserInfo([
                    "csvText": csvText,
                    "filename": filename,
                    "startedAt": startedAt.timeIntervalSince1970,
                ])
            }
        }

        /// Retries any locally cached debug CSVs that are not already in WatchConnectivity's transfer queue.
        func flushPendingMotionCSVs() {
            guard WCSession.isSupported(), session.activationState == .activated else { return }

            let outstandingURLs = Set(session.outstandingFileTransfers.map(\.file.fileURL.standardizedFileURL))
            for fileURL in pendingMotionCSVURLs() where !outstandingURLs.contains(fileURL.standardizedFileURL) {
                session.transferFile(fileURL, metadata: ["filename": fileURL.lastPathComponent])
                print("[WatchConnectivityManager] Re-queued pending motion CSV: \(fileURL.lastPathComponent)")
            }
        }

        /// Cleans up transferred debug CSV files once WatchConnectivity confirms delivery.
        nonisolated func session(_: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
            let fileURL = fileTransfer.file.fileURL
            let errorDescription = error?.localizedDescription
            Task { @MainActor [weak self] in
                self?.handleCompletedFileTransfer(fileURL: fileURL, errorDescription: errorDescription)
            }
        }
    #endif

    /// Applies reachable settings messages or action requests from the iPhone app.
    nonisolated func session(_: WCSession, didReceiveMessage message: [String: Any]) {
        print("[WatchConnectivityManager] Received message: \(message)")
        if let action = message["action"] as? String, action == "stopWorkout" {
            Task { @MainActor in
                // If the watch session is active, finish the workout upon remote iPhone request.
                JumpRecState.shared.end()
            }
            return
        }
        parseSettingsPayload(message)
    }

    /// Reports lifecycle changes without waiting for HealthKit mirroring.
    func sendWorkoutEvent(_ payload: MirroredWorkoutPayload) {
        do {
            let data = try JSONEncoder().encode(payload)
            sendMessage(["workoutEvent": data])
        } catch {
            print("[WatchConnectivityManager] Failed to encode workout event: \(error)")
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
        doubleUndersCount: Int,
        averageHeartRate: Int?,
        peakHeartRate: Int?,
        goalType: GoalType
    ) {
        var payload: [String: Any] = [
            "type": "sessionComplete",
            "startedAt": startedAt.timeIntervalSince1970,
            "endedAt": endedAt.timeIntervalSince1970,
            "jumpCount": jumpCount,
            "caloriesBurned": caloriesBurned,
            "jumpOffsets": jumpOffsets,
            "doubleUndersCount": doubleUndersCount,
            "goalType": goalType.rawValue,
        ]
        payload["averageHeartRate"] = averageHeartRate
        payload["peakHeartRate"] = peakHeartRate
        session.transferUserInfo(payload)
        print("[WatchConnectivityManager] Queued completed session via transferUserInfo")
    }

    /// Logs changes to reachability with the iPhone app.
    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let isReachable = session.isReachable
        print("[WatchConnectivityManager] Session reachability changed: \(isReachable)")
        #if DEBUG
            if isReachable {
                Task { @MainActor [weak self] in
                    self?.flushPendingMotionCSVs()
                }
            }
        #endif
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

        let shouldSpeakJumpCountAnnouncements = payload["shouldSpeakJumpCountAnnouncements"] as? Bool ?? true
        let shouldSpeakJumpTimeAnnouncements = payload["shouldSpeakJumpTimeAnnouncements"] as? Bool ?? true
        let jumpDetectorThresholdAdjustmentPercentage = (payload["jumpDetectorThresholdAdjustmentPercentage"] as? NSNumber)?.doubleValue
            ?? 0.0
        let hasUnlockedUnlimitedWorkouts = payload["hasUnlockedUnlimitedWorkouts"] as? Bool
        let qualifiedWorkoutCount = (payload["qualifiedWorkoutCount"] as? NSNumber)?.intValue
        let accentColor = (payload["accentColor"] as? String).flatMap(AppAccentColor.init(rawValue:))

        Task { @MainActor [weak self] in
            // Missing or unknown colors from older companions leave the current accent intact.
            if let accentColor {
                AppAppearance.shared.accent = accentColor
            }
            self?.applySettings(
                goalTypeRawValue: goalTypeRawValue,
                jumpCount: jumpCount,
                jumpTime: jumpTime,
                shouldSpeakJumpCountAnnouncements: shouldSpeakJumpCountAnnouncements,
                shouldSpeakJumpTimeAnnouncements: shouldSpeakJumpTimeAnnouncements,
                jumpDetectorThresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage,
                hasUnlockedUnlimitedWorkouts: hasUnlockedUnlimitedWorkouts,
                qualifiedWorkoutCount: qualifiedWorkoutCount
            )
        }
    }

    /// Persists parsed settings and notifies main-actor observers.
    private func applySettings(
        goalTypeRawValue: String,
        jumpCount: Int,
        jumpTime: Int,
        shouldSpeakJumpCountAnnouncements: Bool,
        shouldSpeakJumpTimeAnnouncements: Bool,
        jumpDetectorThresholdAdjustmentPercentage: Double,
        hasUnlockedUnlimitedWorkouts: Bool?,
        qualifiedWorkoutCount: Int?
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
        if let hasUnlockedUnlimitedWorkouts {
            settingsStore.set(hasUnlockedUnlimitedWorkouts, forKey: "hasUnlockedUnlimitedWorkouts")
        }
        if let qualifiedWorkoutCount {
            settingsStore.set(Int64(qualifiedWorkoutCount), forKey: "qualifiedWorkoutCount")
        }
        settingsStore.synchronize()

        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }

    #if DEBUG
        /// Directory storing debug motion CSV files until WatchConnectivity finishes transferring them.
        private var pendingMotionCSVDirectoryURL: URL {
            let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            return cachesURL.appendingPathComponent("PendingDebugMotionCSV", isDirectory: true)
        }

        /// Writes a debug CSV to the pending directory so it survives interrupted transfers.
        private func writePendingMotionCSV(csvText: String, filename: String) throws -> URL {
            let directoryURL = pendingMotionCSVDirectoryURL
            if !FileManager.default.fileExists(atPath: directoryURL.path) {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            }
            let fileURL = directoryURL.appendingPathComponent(filename)
            try csvText.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        }

        /// Lists cached debug CSV files waiting for successful transfer.
        private func pendingMotionCSVURLs() -> [URL] {
            let directoryURL = pendingMotionCSVDirectoryURL
            guard let urls = try? FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else {
                return []
            }
            return urls.filter { $0.pathExtension.lowercased() == "csv" }
        }

        /// Deletes the local staging copy only after WatchConnectivity succeeds.
        private func handleCompletedFileTransfer(fileURL: URL, errorDescription: String?) {
            if let errorDescription {
                print("[WatchConnectivityManager] Failed to transfer motion CSV \(fileURL.lastPathComponent): \(errorDescription)")
                return
            }

            let pendingPath = pendingMotionCSVDirectoryURL.standardizedFileURL.path
            guard fileURL.standardizedFileURL.path.hasPrefix(pendingPath) else { return }

            do {
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                print("[WatchConnectivityManager] Cleaned up transferred motion CSV: \(fileURL.lastPathComponent)")
            } catch {
                print("[WatchConnectivityManager] Failed to remove transferred motion CSV: \(error.localizedDescription)")
            }
        }
    #endif
}
