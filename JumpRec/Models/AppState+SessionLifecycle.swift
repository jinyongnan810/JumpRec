//
//  AppState+SessionLifecycle.swift
//  JumpRec
//

import Foundation
import UIKit

extension JumpRecState {
    // MARK: - Session Lifecycle

    /// Starts a session locally or requests a mirrored watch session when available.
    func start(goalType: GoalType, goalValue: Int) {
        // Enter a transient starting state immediately so the home screen can
        // block duplicate taps while the watch companion workout request is in flight.
        sessionGoalType = goalType
        sessionGoalValue = goalValue
        sessionState = .starting

        if connectivityManager.isPaired, connectivityManager.isWatchAppInstalled {
            pendingMirroredStart = true
            connectivityManager.syncSettings(
                goalType: goalType,
                jumpCount: Int64(goalType == .count ? goalValue : 0),
                jumpTime: Int64(goalType == .time ? goalValue : 0)
            )

            Task {
                do {
                    try await workoutMirrorManager.startCompanionWorkout()
                } catch {
                    await MainActor.run {
                        // If watch startup fails, fall back to an iPhone-tracked session
                        // instead of leaving the UI stuck in the pending-start state.
                        self.pendingMirroredStart = false
                        self.startLocalSession(goalType: goalType, goalValue: goalValue)
                    }
                }
            }
            return
        }

        startLocalSession(goalType: goalType, goalValue: goalValue)
    }

    /// Finishes the active local session and persists its results.
    func finish() {
        guard sessionState == .active, let startTime else { return }
        guard !isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        motionManager?.stopTracking()
        let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        endTime = Date()
        if let endTime {
            Task {
                await phoneWorkoutManager.endWorkout(at: endTime)
            }
        }
        sessionState = .complete
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionFinishedAnnouncement)
        syncLiveActivity()

        if let endTime {
            completedSession = dataStore.saveCompletedSession(
                startedAt: startTime,
                endedAt: endTime,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumps,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )
            exportMotionCSVIfNeeded(samples: motionSamples, startedAt: startTime, endedAt: endTime)
        }
    }

    /// Updates scene activity to keep the idle timer in sync.
    func updateSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        syncIdleTimer()
    }

    /// Resets the app back to its idle state and clears active session data.
    func reset() {
        invalidateMinuteTimer()
        motionManager?.stopTracking()
        phoneWorkoutManager.discardWorkout()
        sessionState = .idle
        resetLiveMetrics()
        activeMotionSource = nil
        motionCSVShareURL = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = nil
        sessionGoalValue = nil
        isMirroredWatchSession = false
        completedSession = nil
        pendingMirroredStart = false
        syncIdleTimer()
        Task {
            await liveActivityManager.endIfNeeded()
        }
    }

    // MARK: - Live Metrics

    /// Applies a newly detected jump from the local motion manager.
    func addJump(from source: MotionManager.Source) {
        guard sessionState == .active, let startTime else { return }

        let resolvedSource = Self.deviceSource(from: source)
        if activeMotionSource == .airpods, resolvedSource == .iPhone {
            return
        }

        activeMotionSource = resolvedSource
        jumpCount += 1
        jumps.append(Date().timeIntervalSince(startTime))
        checkFeedbackLandmarks()
        syncLiveActivity()
        finishIfGoalReached()
    }

    /// Starts a session that is tracked directly on the iPhone.
    func startLocalSession(goalType: GoalType, goalValue: Int) {
        let sessionStartDate = Date()
        invalidateMinuteTimer()
        resetLiveMetrics()
        completedSession = nil
        startTime = sessionStartDate
        endTime = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = goalType
        sessionGoalValue = goalValue
        isMirroredWatchSession = false
        pendingMirroredStart = false
        sessionState = .active
        motionManager?.startTracking()
        // Start minute announcements for every session so users hear elapsed time
        // even when the selected goal is jump-based. Goal completion still remains
        // controlled by `isGoalReached(referenceDate:)`.
        startMinuteTimer()
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionStartedAnnouncement)
        syncLiveActivity()
        Task {
            do {
                try await phoneWorkoutManager.startWorkout(at: sessionStartDate)
            } catch {
                print("[JumpRecState] Failed to start iPhone workout session: \(error)")
            }
        }
    }

    /// Clears the live metrics used by the active session UI.
    func resetLiveMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        caloriesBurned = 0
        startTime = nil
        endTime = nil
    }

    // MARK: - Goal Tracking

    /// Announces major jump milestones for local sessions.
    func checkFeedbackLandmarks() {
        guard !isMirroredWatchSession else { return }

        // Count landmarks are useful progress cues regardless of whether the user
        // is chasing a jump target or a time target, so the announcement is no
        // longer restricted to count-goal sessions.
        if jumpCount > 0, jumpCount.isMultiple(of: 100) {
            notificationFeedbackGenerator.notificationOccurred(.success)
            notificationFeedbackGenerator.prepare()
            speak(text: localizedJumpAnnouncement(for: jumpCount))
        }
    }

    /// Starts the timer used for time-based goal announcements.
    func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
        }
    }

    /// Invalidates the active minute timer.
    func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    /// Announces each elapsed minute.
    ///
    /// Time-goal sessions still end from this callback once the configured duration
    /// has been met. Count-goal sessions keep running and only use this path for
    /// spoken progress so the user hears both time and jump milestones.
    private func handleMinuteLandmark() {
        guard sessionState == .active, !isMirroredWatchSession, let startTime else {
            return
        }

        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        guard minutesElapsed > 0 else { return }

        if sessionGoalType == .time, isGoalReached(referenceDate: Date()) {
            finish()
            return
        }

        notificationFeedbackGenerator.notificationOccurred(.success)
        notificationFeedbackGenerator.prepare()
        speak(text: localizedMinuteAnnouncement(for: minutesElapsed))
    }

    /// Finishes the session immediately when the goal is satisfied.
    func finishIfGoalReached() {
        guard isGoalReached(referenceDate: Date()) else { return }
        finish()
    }

    /// Returns whether the active goal has been reached at the given time.
    private func isGoalReached(referenceDate: Date) -> Bool {
        guard sessionState == .active,
              !isMirroredWatchSession,
              let goalType = sessionGoalType,
              let goalValue = sessionGoalValue
        else {
            return false
        }

        switch goalType {
        case .count:
            return jumpCount >= goalValue
        case .time:
            guard let startTime else { return false }
            return Int(referenceDate.timeIntervalSince(startTime)) >= goalValue * 60
        @unknown default:
            return false
        }
    }
}
