//
//  AppState.swift
//  JumpRec
//

import AVFoundation
import Foundation
import Observation
import UIKit

/// Owns iPhone workout state; main-actor isolation protects unchecked Sendable delegate state.
@Observable
@MainActor
final class JumpRecState: NSObject, @unchecked Sendable {
    // MARK: - Configuration

    /// Enables CSV motion export for debug builds.
    let isMotionCSVExportEnabled = {
        #if DEBUG
            true
        #else
            false
        #endif
    }()

    // MARK: - App Intents Coordination

    /// Weak reference used by foreground App Intents to coordinate workouts.
    weak static var current: JumpRecState?

    /// Stores a pending start goal requested by an App Intent before the UI has finished loading.
    static var pendingStartGoal: (type: GoalType, value: Int)?

    /// Observable start request handled by the root view's quota and settings policy.
    struct WorkoutStartRequest: Equatable {
        let type: GoalType
        let value: Int
    }

    /// Foreground intents publish here; ContentView consumes and clears the request.
    var requestedStartGoal: WorkoutStartRequest?

    // MARK: - Session State

    /// Tracks the current lifecycle state of the session UI.
    var sessionState: SessionState = .idle
    /// Stores when the current or last session started.
    var startTime: Date?
    /// Stores when the current or last session ended.
    var endTime: Date?
    /// Stores the total number of detected jumps in the active session.
    var jumpCount = 0
    /// Stores jump offsets relative to `startTime`.
    var jumps: [TimeInterval] = []
    /// Stores the latest calorie estimate for the session.
    var caloriesBurned = 0.0
    /// Stores the most recently sampled current heart rate in bpm during an active session.
    var heartRate: Int?
    /// Stores the average heart rate for the completed session when available.
    var averageHeartRate: Int?
    /// Stores the peak heart rate for the completed session when available.
    var peakHeartRate: Int?
    /// Stores the selected goal type for the active session.
    var sessionGoalType: GoalType?
    /// Stores the selected goal value for the active session: jumps for count goals, minutes for time goals.
    var sessionGoalValue: Int?
    /// Indicates whether the current session is being mirrored from Apple Watch.
    var isMirroredWatchSession = false
    /// Enables jump announcements for the active session; updated from settings.
    var sessionShouldSpeakJumpCountAnnouncements = true
    /// Enables spoken minute cues without affecting goal completion or haptics.
    var sessionShouldSpeakJumpTimeAnnouncements = true
    /// Stores the saved session shown on the completion screen.
    var completedSession: JumpSession?

    // MARK: - Motion State

    /// Indicates which device is currently providing motion data.
    var activeMotionSource: DeviceSource?
    /// Indicates whether iPhone motion is currently available.
    var isPhoneMotionAvailable = false
    /// Indicates whether headphone motion is currently available.
    var isHeadphoneMotionAvailable = false
    /// Stores the current headphone route name so the selector can show a real product label when iOS provides one.
    var connectedHeadphoneName: String?
    #if DEBUG
        /// Stores the exported motion CSV URL when debug export is enabled.
        var motionCSVShareURL: URL?
    #endif

    /// Provides shared persistence and session-generation helpers.
    @ObservationIgnored
    let dataStore = MyDataStore.shared
    /// Tracks whether the scene is active for idle-timer management.
    @ObservationIgnored
    var isSceneActive = false
    /// Remembers when a mirrored start request is waiting for watch confirmation.
    @ObservationIgnored
    var pendingMirroredStart = false
    /// Session token rejects stale asynchronous HealthKit completions after reset or replacement.
    @ObservationIgnored
    var sessionGeneration = UUID()
    /// Owns the request that asks Apple Watch to start a companion workout.
    @ObservationIgnored
    var companionWorkoutStartTask: Task<Void, Never>?
    /// Serializes local HealthKit workout start and end operations.
    @ObservationIgnored
    var phoneWorkoutLifecycleTask: Task<Void, Never>?

    // MARK: - Dependencies

    /// Detects local motion data and jump events.
    @ObservationIgnored
    var motionManager: MotionManager?
    /// Coordinates HealthKit workout mirroring from Apple Watch.
    @ObservationIgnored
    let workoutMirrorManager = WorkoutMirrorManager.shared
    /// Manages iPhone HealthKit workouts.
    @ObservationIgnored
    let phoneWorkoutManager = PhoneWorkoutManager.shared
    /// Manages watch connectivity and file transfer.
    @ObservationIgnored
    let connectivityManager = ConnectivityManager.shared
    /// Manages live-activity presentation and updates.
    @ObservationIgnored
    let liveActivityManager = LiveActivityManager.shared
    /// Serializes Live Activity calls and cancels superseded metric updates.
    @ObservationIgnored
    var liveActivitySyncTask: Task<Void, Never>?
    /// Speaks audible session prompts and milestones.
    @ObservationIgnored
    let synthesizer = AVSpeechSynthesizer()
    /// Tracks the one-time speech warmup for this app lifetime.
    @ObservationIgnored
    var hasWarmedUpSpeechSynthesizer = false
    /// Marks silent warmup speech so a real announcement can interrupt it.
    @ObservationIgnored
    var isSpeechWarmupInProgress = false
    /// Owns the latest delayed speech request so obsolete session cues can be cancelled.
    @ObservationIgnored
    var pendingSpeechTask: Task<Void, Never>?
    /// Identifies the latest speech request even when an older cancelled task resumes.
    @ObservationIgnored
    var pendingSpeechRequestID = UUID()
    /// Emits haptic feedback for session events.
    @ObservationIgnored
    let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
    /// Cancellable minute-announcement task owned by the current session.
    @ObservationIgnored
    var minuteAnnouncementTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Configures managers, callback wiring, audio, and haptics.
    override init() {
        super.init()
        Self.current = self
        motionManager = MotionManager(
            shouldRecordMotionSamples: isMotionCSVExportEnabled,
            onJumpDetected: { [weak self] source in
                self?.addJump(from: source)
            },
            onSourceChanged: { [weak self] source in
                self?.activeMotionSource = Self.deviceSource(from: source)
            },
            onAvailabilityChanged: { [weak self] isPhoneAvailable, isHeadphoneAvailable, headphoneName in
                self?.isPhoneMotionAvailable = isPhoneAvailable
                self?.isHeadphoneMotionAvailable = isHeadphoneAvailable
                self?.connectedHeadphoneName = headphoneName
            }
        )
        motionManager?.refreshAvailability()
        workoutMirrorManager.onPayloadReceived = { [weak self] payload in
            self?.handleMirroredWorkoutPayload(payload)
        }
        workoutMirrorManager.onMirroredSessionEnded = { [weak self] in
            self?.handleMirroredSessionEnded()
        }
        phoneWorkoutManager.onMetricsUpdated = { [weak self] caloriesBurned, heartRate, averageHeartRate, peakHeartRate in
            guard let self else { return }
            guard sessionState == .active, !isMirroredWatchSession else { return }

            self.caloriesBurned = caloriesBurned
            self.heartRate = heartRate
            self.averageHeartRate = averageHeartRate
            self.peakHeartRate = peakHeartRate
            syncLiveActivity()
        }
        connectivityManager.onCompletedSessionReceived = { [weak self] startedAt, endedAt, jumpCount, caloriesBurned, jumpOffsets, averageHeartRate, peakHeartRate, session in
            self?.applyCompletedWatchSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate,
                session: session
            )
        }
        // The delegate restores background-audio volume after speech finishes.
        synthesizer.delegate = self
        prepareHaptics()
    }

    // MARK: - Derived Values

    /// Returns the current session duration in seconds.
    var durationSeconds: Int {
        guard let startTime else { return 0 }
        let end = endTime ?? Date()
        return max(0, Int(end.timeIntervalSince(startTime)))
    }

    /// Returns the current session duration formatted as `mm:ss`.
    var elapsedFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Returns the current average jump rate in jumps per minute.
    var averageRate: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(jumpCount) * 60.0 / Double(durationSeconds)).rounded())
    }

    /// Returns the derived break metrics for the current session.
    var breakMetrics: (small: Int, long: Int, longestStreak: Int) {
        SessionMetricsCalculator.breakMetrics(from: jumps)
    }

    /// Converts a motion-manager source into a shared display source.
    static func deviceSource(from source: MotionManager.Source?) -> DeviceSource? {
        switch source {
        case .iPhone:
            .iPhone
        case .headphones:
            .airpods
        case nil:
            nil
        }
    }
}
