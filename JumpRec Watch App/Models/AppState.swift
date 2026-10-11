//
//  AppState.swift
//  JumpRec
//
//  Created by kinn on 2025/10/05.
//

import AVFoundation
import Foundation
import Observation

enum JumpState {
    /// No workout is running.
    case idle, jumping, finished
}

/// Owns Watch workout state; main-actor isolation protects unchecked Sendable delegate state.
@Observable
@MainActor
class JumpRecState: NSObject, @unchecked Sendable {
    // MARK: - Shared Instance

    /// Provides the single shared app state used across watch views.
    static let shared = JumpRecState()

    // MARK: - Session State

    /// Tracks the current watch-side session state.
    var jumpState: JumpState = .idle
    /// Stores when the current or last session started.
    var startTime: Date?
    /// Stores when the current or last session ended.
    var endTime: Date?
    /// Stores the total jump count for the session.
    var jumpCount: Int = 0
    /// Stores jump offsets relative to `startTime`.
    var jumps: [TimeInterval] = []
    /// Stores the latest heart-rate sample.
    var heartrate: Int = 0
    /// Accumulates heart-rate samples for average calculation.
    @ObservationIgnored
    var heartRateSum: Int = 0
    /// Counts heart-rate samples used for averaging.
    @ObservationIgnored
    var heartRateSampleCount: Int = 0
    /// Stores the highest observed heart rate.
    @ObservationIgnored
    var peakHeartRate: Int = 0
    /// Stores the latest calorie estimate from HealthKit.
    var energyBurned: Double = 0
    /// Stores the active goal type for the session.
    var goalType: GoalType = .count
    /// Active goal in jumps for count goals or seconds for time goals.
    var goal: Int = 0
    /// Enables Watch jump announcements; refreshed from synced settings.
    var sessionShouldSpeakJumpCountAnnouncements = true
    /// Enables spoken minute cues without affecting time-goal completion.
    var sessionShouldSpeakJumpTimeAnnouncements = true
    /// Returns the finished session duration formatted as `mm:ss`.
    var totalTime: String {
        guard let startTime, let endTime else { return "00:00" }
        let timeInterval: TimeInterval = endTime.timeIntervalSince(startTime)
        let minutes = Int(timeInterval) / 60
        let seconds = Int(timeInterval).remainderReportingOverflow(dividingBy: 60).partialValue
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Speaks workout announcements on Apple Watch.
    @ObservationIgnored
    let synthesizer = AVSpeechSynthesizer()
    /// Tracks the one-time speech warmup for this app lifetime.
    @ObservationIgnored
    var hasWarmedUpSpeechSynthesizer = false
    /// Marks silent warmup speech so real announcements can interrupt it.
    @ObservationIgnored
    var isSpeechWarmupInProgress = false
    /// Owns the latest delayed speech request so obsolete workout cues can be cancelled.
    @ObservationIgnored
    var pendingSpeechTask: Task<Void, Never>?
    /// Identifies the latest speech request even when an older cancelled task resumes.
    @ObservationIgnored
    var pendingSpeechRequestID = UUID()

    /// Detects watch motion and jump events.
    @ObservationIgnored
    var motionManager: MotionManager?
    /// Cancellable minute-announcement task owned by the current workout.
    @ObservationIgnored
    var minuteAnnouncementTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Configures motion tracking and speech for the watch app.
    override init() {
        super.init()
        motionManager = MotionManager(addJump: { by in
            Task { @MainActor in
                self.addJump(by: by)
            }
        }, updateHeartRate: { heartRate in
            Task { @MainActor in
                self.recordHeartRate(heartRate)
            }
        }, updateEnergyBurned: { energyBurned in
            Task { @MainActor in
                // Assign cumulative total active energy burned received from HealthKit
                self.energyBurned = energyBurned
            }
        })
        // The delegate releases ducking audio after speech finishes.
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            forName: .jumpRecSettingsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // Read the synced snapshot after WatchConnectivity persists it and posts the notification.
            Task { @MainActor [weak self] in
                self?.applySyncedSettingsFromStore()
            }
        }
    }

    /// Applies a synced settings snapshot to the active workout without creating an observer.
    private func applySyncedSettingsFromStore() {
        let store = NSUbiquitousKeyValueStore.default
        store.synchronize()

        let goalType: GoalType = store.string(forKey: "goalType") == GoalType.time.rawValue ? .time : .count
        let storedJumpCount = store.longLong(forKey: "jumpCount")
        let storedJumpTime = store.longLong(forKey: "jumpTime")
        let jumpCount = storedJumpCount == 0 ? DefaultJumpCount : storedJumpCount
        let jumpTime = storedJumpTime == 0 ? DefaultJumpTime : storedJumpTime
        let shouldSpeakJumpCountAnnouncements = store.object(forKey: "shouldSpeakJumpCountAnnouncements") as? Bool ?? true
        let shouldSpeakJumpTimeAnnouncements = store.object(forKey: "shouldSpeakJumpTimeAnnouncements") as? Bool ?? true
        let thresholdAdjustmentPercentage = (store.object(forKey: "jumpDetectorThresholdAdjustmentPercentage") as? NSNumber)?.doubleValue
            ?? DefaultJumpDetectorThresholdAdjustmentPercentage

        applyActiveSessionSettings(
            goalType: goalType,
            goalCount: Int(goalType == .count ? jumpCount : jumpTime),
            shouldSpeakJumpCountAnnouncements: shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: JumpRecSettings.clampedJumpDetectorThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
        )
    }
}
