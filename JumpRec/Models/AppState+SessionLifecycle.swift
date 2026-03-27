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
        cancelSessionLifecycleTasks()
        sessionGoalType = goalType
        sessionGoalValue = goalValue

        if connectivityManager.isPaired, connectivityManager.isWatchAppInstalled {
            pendingMirroredStart = true
            connectivityManager.syncSettings(
                goalType: goalType,
                jumpCount: Int64(goalType == .count ? goalValue : 0),
                jumpTime: Int64(goalType == .time ? goalValue : 0)
            )

            companionWorkoutTask = Task { [weak self] in
                guard let self else { return }
                do {
                    try await workoutMirrorManager.startCompanionWorkout()
                } catch is CancellationError {
                    // The user reset or restarted the flow before the watch launch finished.
                } catch {
                    guard !Task.isCancelled, pendingMirroredStart else { return }
                    pendingMirroredStart = false
                    startLocalSession(goalType: goalType, goalValue: goalValue)
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
        cancelPhoneWorkoutTasks()
        motionManager?.stopTracking()
        let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        endTime = Date()
        if let endTime {
            phoneWorkoutEndTask = Task { [weak self] in
                guard let self else { return }
                await phoneWorkoutManager.endWorkout(at: endTime)
                guard !Task.isCancelled else { return }
                phoneWorkoutEndTask = nil
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
        cancelSessionLifecycleTasks()
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
        syncLiveActivity()
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
        if goalType == .time {
            startMinuteTimer()
        }
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionStartedAnnouncement)
        syncLiveActivity()
        phoneWorkoutStartTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await phoneWorkoutManager.startWorkout(at: sessionStartDate)
            } catch is CancellationError {
                // A new session state replaced this one before HealthKit finished starting.
            } catch {
                print("[JumpRecState] Failed to start iPhone workout session: \(error)")
            }
            guard !Task.isCancelled, sessionState == .active, startTime == sessionStartDate else { return }
            phoneWorkoutStartTask = nil
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

        if sessionGoalType == .count, jumpCount > 0, jumpCount.isMultiple(of: 100) {
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

    /// Announces a minute milestone and ends the session if the time goal is reached.
    private func handleMinuteLandmark() {
        guard sessionState == .active, !isMirroredWatchSession, sessionGoalType == .time, let startTime else {
            return
        }

        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        guard minutesElapsed > 0 else { return }

        if isGoalReached(referenceDate: Date()) {
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

    /// Cancels all unstructured tasks that belong to the current session lifecycle.
    private func cancelSessionLifecycleTasks() {
        companionWorkoutTask?.cancel()
        companionWorkoutTask = nil
        cancelPhoneWorkoutTasks()
        liveActivityTask?.cancel()
        liveActivityTask = nil
    }

    /// Cancels the in-flight HealthKit start/end requests before replacing them with newer state.
    private func cancelPhoneWorkoutTasks() {
        phoneWorkoutStartTask?.cancel()
        phoneWorkoutStartTask = nil
        phoneWorkoutEndTask?.cancel()
        phoneWorkoutEndTask = nil
    }
}
