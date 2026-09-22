//
//  AppState.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/10/05.
//

import AVFoundation
import Foundation
import Observation

enum JumpState {
    /// No workout is running.
    case idle, jumping, finished
}

/// Owns the watch app's session lifecycle, motion tracking, and mirrored workout updates.
///
/// `JumpRecState` inherits from `NSObject` to serve as an `AVSpeechSynthesizerDelegate`.
/// Since its mutable state is completely isolated to the `@MainActor`, it is marked `@unchecked Sendable`
/// here in its primary declaration to satisfy concurrency requirements for delegate protocols.
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
    /// Stores the active goal value: jumps for count goals, seconds for time goals after converting from the minute-based setting.
    var goal: Int = 0
    /// Stores whether jump-count announcements should play for the active watch session.
    ///
    /// The value is seeded from shared settings when the workout starts and refreshed
    /// when the paired iPhone sends an in-session settings update.
    var sessionShouldSpeakJumpCountAnnouncements = true
    /// Stores whether elapsed-time announcements should play for the active watch session.
    ///
    /// The minute timer still drives time-goal completion when this is disabled; only
    /// the spoken progress cue is muted.
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
    /// Tracks whether the synthesizer has already been primed during this app lifetime.
    ///
    /// The first spoken announcement can stall while watchOS initializes the speech
    /// pipeline. Keeping this flag on the shared state lets the root view request a
    /// one-time warmup without repeating the work every time SwiftUI re-renders.
    @ObservationIgnored
    var hasWarmedUpSpeechSynthesizer = false
    /// Tracks whether a silent warmup utterance is currently using the synthesizer.
    ///
    /// Real workout announcements should not wait for the zero-volume warmup to
    /// complete. This flag lets the speech path cancel the warmup immediately when a
    /// user-visible prompt is ready to play.
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
    /// Owns the cancellable task that announces elapsed-minute milestones.
    ///
    /// Retaining the task lets session cleanup stop a pending sleep before another
    /// workout starts, avoiding announcements that belong to the previous workout.
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
        // The synthesizer delegate releases the speech audio session after each spoken
        // prompt so the watch only ducks other audio while it is actively speaking.
        synthesizer.delegate = self
        NotificationCenter.default.addObserver(
            forName: .jumpRecSettingsDidUpdate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            // WatchConnectivity writes the latest settings to shared storage before posting
            // this notification. App state reads the small snapshot directly here so it does
            // not create extra observable settings objects just to update a running workout.
            Task { @MainActor [weak self] in
                self?.applySyncedSettingsFromStore()
            }
        }
    }

    /// Reads the latest synced settings snapshot and applies it to a running workout.
    ///
    /// This intentionally mirrors `JumpRecSettings.loadSettings()` for the small subset
    /// needed by active sessions, while avoiding construction of a new observable settings
    /// object from inside every WatchConnectivity notification.
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
