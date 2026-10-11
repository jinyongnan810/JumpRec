//
//  AppState+SessionLifecycle.swift
//  JumpRec
//

import Foundation
import UIKit

extension JumpRecState {
    // MARK: - Session Lifecycle

    /// Starts locally or on Watch; the caller resolves headphone availability and preference.
    func start(
        goalType: GoalType,
        goalValue: Int,
        preferLocalHeadphonesOverWatch: Bool = false,
        shouldSpeakJumpCountAnnouncements: Bool = true,
        shouldSpeakJumpTimeAnnouncements: Bool = true,
        jumpDetectorThresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage
    ) {
        cancelPendingSpeech()
        let generation = beginSessionAttempt()

        // Enter the starting state to block duplicate requests during the Watch handshake.
        sessionGoalType = goalType
        sessionGoalValue = goalValue
        sessionShouldSpeakJumpCountAnnouncements = shouldSpeakJumpCountAnnouncements
        sessionShouldSpeakJumpTimeAnnouncements = shouldSpeakJumpTimeAnnouncements
        sessionState = .starting

        if connectivityManager.isPaired,
           connectivityManager.isWatchAppInstalled,
           !preferLocalHeadphonesOverWatch
        {
            pendingMirroredStart = true
            connectivityManager.syncSettings(
                goalType: goalType,
                jumpCount: Int64(goalType == .count ? goalValue : 0),
                jumpTime: Int64(goalType == .time ? goalValue : 0),
                shouldSpeakJumpCountAnnouncements: shouldSpeakJumpCountAnnouncements,
                shouldSpeakJumpTimeAnnouncements: shouldSpeakJumpTimeAnnouncements,
                jumpDetectorThresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage
            )

            companionWorkoutStartTask = Task { [weak self, workoutMirrorManager] in
                do {
                    try await workoutMirrorManager.startCompanionWorkout()
                } catch {
                    guard let self,
                          !Task.isCancelled,
                          sessionGeneration == generation,
                          sessionState == .starting,
                          pendingMirroredStart
                    else {
                        return
                    }

                    // Fall back to local tracking only if this request still owns startup.
                    pendingMirroredStart = false
                    startLocalSession(
                        goalType: goalType,
                        goalValue: goalValue,
                        thresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage,
                        generation: generation
                    )
                }
            }
            return
        }

        startLocalSession(
            goalType: goalType,
            goalValue: goalValue,
            thresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage,
            generation: generation
        )
    }

    /// Applies live settings; Watch remains responsible for ending mirrored workouts.
    func applyActiveSessionSettings(
        goalType: GoalType,
        goalValue: Int,
        shouldSpeakJumpCountAnnouncements: Bool,
        shouldSpeakJumpTimeAnnouncements: Bool,
        jumpDetectorThresholdAdjustmentPercentage: Double
    ) {
        guard sessionState == .active else { return }

        sessionGoalType = goalType
        sessionGoalValue = goalValue
        sessionShouldSpeakJumpCountAnnouncements = shouldSpeakJumpCountAnnouncements
        sessionShouldSpeakJumpTimeAnnouncements = shouldSpeakJumpTimeAnnouncements

        if !isMirroredWatchSession {
            motionManager?.updateThresholdAdjustmentPercentage(jumpDetectorThresholdAdjustmentPercentage)
            finishIfGoalReached()
        }

        syncLiveActivity()
    }

    /// Saves local results, or requests Watch to finish and return mirrored results.
    func finish() {
        guard sessionState == .active, let startTime else { return }

        if isMirroredWatchSession {
            cancelMinuteAnnouncements()
            ConnectivityManager.shared.sendStopSessionCommand()
            return
        }

        cancelMinuteAnnouncements()
        motionManager?.stopTracking()
        let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        endTime = Date()
        sessionState = .complete

        if let endTime {
            let precedingWorkoutTask = phoneWorkoutLifecycleTask
            phoneWorkoutLifecycleTask = Task { [phoneWorkoutManager] in
                // Wait for HealthKit startup before ending so a late start cannot leave a workout running.
                await precedingWorkoutTask?.value

                // Finish saving even if Done resets the completion screen first.
                await phoneWorkoutManager.endWorkout(at: endTime)
            }
        }
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
            #if DEBUG
                exportMotionCSVIfNeeded(samples: motionSamples, startedAt: startTime, endedAt: endTime)
            #endif
        }
    }

    /// Updates scene activity to keep the idle timer in sync.
    func updateSceneActive(_ isActive: Bool) {
        isSceneActive = isActive
        syncIdleTimer()
    }

    /// Resets the app back to its idle state and clears active session data.
    func reset() {
        let shouldFinishSavingCompletedWorkout = sessionState == .complete && !isMirroredWatchSession
        invalidateWorkoutOperations(cancelPhoneWorkoutTask: !shouldFinishSavingCompletedWorkout)
        cancelPendingSpeech()
        cancelMinuteAnnouncements()
        motionManager?.stopTracking()

        // Preserve completed-workout finalization when Done resets the UI.
        if !shouldFinishSavingCompletedWorkout {
            phoneWorkoutManager.discardWorkout()
        }
        sessionState = .idle
        resetLiveMetrics()
        activeMotionSource = nil
        #if DEBUG
            motionCSVShareURL = nil
        #endif
        heartRate = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = nil
        sessionGoalValue = nil
        sessionShouldSpeakJumpCountAnnouncements = true
        sessionShouldSpeakJumpTimeAnnouncements = true
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
    private func startLocalSession(
        goalType: GoalType,
        goalValue: Int,
        thresholdAdjustmentPercentage: Double,
        generation: UUID
    ) {
        guard sessionGeneration == generation else { return }

        companionWorkoutStartTask?.cancel()
        companionWorkoutStartTask = nil

        let sessionStartDate = Date()
        cancelMinuteAnnouncements()
        resetLiveMetrics()
        completedSession = nil
        startTime = sessionStartDate
        endTime = nil
        heartRate = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = goalType
        sessionGoalValue = goalValue
        isMirroredWatchSession = false
        pendingMirroredStart = false
        sessionState = .active
        motionManager?.startTracking(thresholdAdjustmentPercentage: thresholdAdjustmentPercentage)
        // Announce elapsed minutes for both goal types; goal completion is checked separately.
        startMinuteAnnouncements()
        syncIdleTimer()
        notificationFeedbackGenerator.notificationOccurred(.success)
        speak(text: localizedSessionStartedAnnouncement)
        syncLiveActivity()
        phoneWorkoutLifecycleTask = Task { [weak self, phoneWorkoutManager] in
            do {
                try await phoneWorkoutManager.startWorkout(at: sessionStartDate)
            } catch {
                guard let self else { return }
                if Task.isCancelled || sessionGeneration != generation {
                    // Discard partial HealthKit state when this operation no longer owns the session.
                    phoneWorkoutManager.discardWorkout()
                    return
                }

                print("[JumpRecState] Failed to start iPhone workout session: \(error)")
                return
            }

            guard let self,
                  !Task.isCancelled,
                  sessionGeneration == generation,
                  sessionState == .active,
                  !isMirroredWatchSession
            else {
                // Discard workouts from stale starts; cancellation cannot stop an in-flight HealthKit call.
                phoneWorkoutManager.discardWorkout()
                return
            }
        }
    }

    /// Creates a fresh identity for a new session and cancels work owned by the previous one.
    private func beginSessionAttempt() -> UUID {
        invalidateWorkoutOperations()
        phoneWorkoutManager.discardWorkout()
        return sessionGeneration
    }

    /// Invalidates asynchronous workout operations without relying on cooperative cancellation alone.
    private func invalidateWorkoutOperations(cancelPhoneWorkoutTask: Bool = true) {
        sessionGeneration = UUID()
        companionWorkoutStartTask?.cancel()
        companionWorkoutStartTask = nil
        if cancelPhoneWorkoutTask {
            phoneWorkoutLifecycleTask?.cancel()
        }
        phoneWorkoutLifecycleTask = nil
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

        // Announce count milestones for both goal types; disabling cues also skips haptics.
        guard sessionShouldSpeakJumpCountAnnouncements else { return }

        if jumpCount > 0, jumpCount.isMultiple(of: 100) {
            notificationFeedbackGenerator.notificationOccurred(.success)
            notificationFeedbackGenerator.prepare()
            speak(text: localizedJumpAnnouncement(for: jumpCount))
        }
    }

    /// Starts cancellable structured-concurrency work for minute announcements.
    func startMinuteAnnouncements() {
        cancelMinuteAnnouncements()
        minuteAnnouncementTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    // Sleep without blocking the main actor between minute cues.
                    try await Task.sleep(for: .seconds(60))
                } catch is CancellationError {
                    return
                } catch {
                    // Exit on sleep errors to avoid a rapid retry loop.
                    return
                }

                guard let self else { return }
                handleMinuteLandmark()
            }
        }
    }

    /// Cancels pending minute-announcement work for the current session.
    func cancelMinuteAnnouncements() {
        minuteAnnouncementTask?.cancel()
        minuteAnnouncementTask = nil
    }

    /// Announces elapsed minutes and finishes time-goal sessions when their duration is reached.
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

        // Skip speech and haptics when minute cues are disabled; goal completion still runs.
        guard sessionShouldSpeakJumpTimeAnnouncements else { return }

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
