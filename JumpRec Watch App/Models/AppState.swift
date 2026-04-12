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
@Observable
@MainActor
class JumpRecState: NSObject {
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

    /// Detects watch motion and jump events.
    @ObservationIgnored
    var motionManager: MotionManager?
    /// Announces minute milestones during time-based sessions.
    @ObservationIgnored
    var minuteTimer: Timer?

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
                self.energyBurned += energyBurned
            }
        })
        // The synthesizer delegate releases the speech audio session after each spoken
        // prompt so the watch only ducks other audio while it is actively speaking.
        synthesizer.delegate = self
    }
}
