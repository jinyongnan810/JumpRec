//
//  AppState+SessionLifecycle.swift
//  JumpRec
//

import Foundation
import WatchKit

extension JumpRecState {
    // MARK: - Session Lifecycle

    /// Warms up speech, motion sensors, and the HealthKit workout session during the countdown.
    func prepareForStart(
        jumpDetectorThresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage
    ) {
        guard jumpState == .idle else { return }
        prepareSpeechForWorkout()
        motionManager?.prepareForWorkout(
            thresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage
        )
    }

    /// Tears down pre-warmed workout resources when the countdown is cancelled before start.
    func cancelPreparedStart() {
        guard jumpState == .idle else { return }
        motionManager?.cancelPreparation()
    }

    /// Starts a Watch workout with settings that can be refreshed during the session.
    func start(
        goalType: GoalType,
        goalCount: Int,
        shouldSpeakJumpCountAnnouncements: Bool = true,
        shouldSpeakJumpTimeAnnouncements: Bool = true,
        jumpDetectorThresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage
    ) {
        cancelPendingSpeech()
        resetSessionMetrics()
        self.goalType = goalType
        sessionShouldSpeakJumpCountAnnouncements = shouldSpeakJumpCountAnnouncements
        sessionShouldSpeakJumpTimeAnnouncements = shouldSpeakJumpTimeAnnouncements
        switch goalType {
        case .count:
            goal = goalCount
        case .time:
            goal = goalCount * 60
        @unknown default:
            goal = goalCount
        }
        startTime = Date()
        if let startTime {
            motionManager?.startTracking(
                startDate: startTime,
                goalType: goalType,
                goalValue: goal,
                thresholdAdjustmentPercentage: jumpDetectorThresholdAdjustmentPercentage
            )
        }
        WKInterfaceDevice.current().play(.start)
        jumpState = .jumping
        // Announce elapsed minutes for both count and time goals.
        startMinuteAnnouncements()
        ConnectivityManager.shared.sendWorkoutEvent(
            MirroredWorkoutPayload(kind: .started, startTime: startTime, goalType: goalType, goalValue: goal)
        )
    }

    /// Starts the local permission check, hardware pre-warm, and three-second countdown from the Watch UI.
    func requestStart(settings: JumpRecSettings) {
        beginWorkoutCountdown(settings: settings, isCompanion: false)
    }

    /// Handles a companion start request across idle, active, and finished Watch states.
    func startFromCompanion() {
        switch jumpState {
        case .jumping:
            resendActiveWorkoutStartToCompanion()
            return
        case .finished:
            reset()
        case .idle:
            break
        }

        beginWorkoutCountdown(settings: nil, isCompanion: true)
    }

    /// Cancels an in-flight permission check or countdown and optionally notifies the companion.
    func cancelPendingStart(notifyCompanion: Bool = true) {
        let wasActive = isPreparingWorkout || isCountingDown || startCountdownTask != nil
        startCountdownTask?.cancel()
        startCountdownTask = nil
        isPreparingWorkout = false
        isCountingDown = false
        countdown = 3

        if wasActive {
            cancelPreparedStart()
        }

        if notifyCompanion {
            notifyCompanionStartCancelledIfNeeded()
        } else {
            isCompanionStartAttempt = false
        }
    }

    /// Prepares permissions, warms sensors, counts down three seconds, and starts the workout.
    private func beginWorkoutCountdown(settings: JumpRecSettings?, isCompanion: Bool) {
        guard jumpState == .idle else { return }

        if isPreparingWorkout || isCountingDown {
            if isCompanion {
                isCompanionStartAttempt = true
            }
            return
        }

        showPermissionError = false
        showQuotaExplanation = false
        if isCompanion {
            isCompanionStartAttempt = true
        }

        let initialSettings = settings.map(Self.storedSettings(from:)) ?? readStoredWorkoutSettings()
        if initialSettings.isQuotaExceeded {
            showQuotaExplanation = true
            notifyCompanionStartCancelledIfNeeded()
            return
        }

        isPreparingWorkout = true
        startCountdownTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                try await WorkoutPermissions.prepareForWorkout()
                try Task.checkCancellation()
            } catch {
                guard !Task.isCancelled else { return }
                isPreparingWorkout = false
                startCountdownTask = nil
                permissionErrorMessage = (error as? WorkoutPermissions.PreparationError)?.localizedDescription
                    ?? String(localized: "Unable to prepare workout permissions. Please try again or review access in Settings.")
                showPermissionError = true
                notifyCompanionStartCancelledIfNeeded()
                return
            }

            guard jumpState == .idle else {
                isPreparingWorkout = false
                startCountdownTask = nil
                return
            }

            let preparedSettings = settings.map(Self.storedSettings(from:)) ?? readStoredWorkoutSettings()
            // Warm up speech, Core Motion, HealthKit session, and mirroring during the countdown.
            prepareForStart(
                jumpDetectorThresholdAdjustmentPercentage: preparedSettings.jumpDetectorThresholdAdjustmentPercentage
            )
            isPreparingWorkout = false
            countdown = 3
            isCountingDown = true

            for value in stride(from: 2, through: 1, by: -1) {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled, jumpState == .idle else {
                    isCountingDown = false
                    startCountdownTask = nil
                    return
                }
                countdown = value
            }

            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard !Task.isCancelled, jumpState == .idle else {
                isCountingDown = false
                startCountdownTask = nil
                return
            }

            isCountingDown = false
            isCompanionStartAttempt = false
            startCountdownTask = nil

            let finalSettings = settings.map(Self.storedSettings(from:)) ?? readStoredWorkoutSettings()
            start(
                goalType: finalSettings.goalType,
                goalCount: finalSettings.goalCount,
                shouldSpeakJumpCountAnnouncements: finalSettings.shouldSpeakJumpCountAnnouncements,
                shouldSpeakJumpTimeAnnouncements: finalSettings.shouldSpeakJumpTimeAnnouncements,
                jumpDetectorThresholdAdjustmentPercentage: finalSettings.jumpDetectorThresholdAdjustmentPercentage
            )
        }
    }

    /// Notifies the companion iPhone app when a companion-triggered start is aborted before running.
    private func notifyCompanionStartCancelledIfNeeded() {
        guard isCompanionStartAttempt else { return }
        isCompanionStartAttempt = false
        ConnectivityManager.shared.sendMessage(["watch app": "startCancelled"])
    }

    /// Re-emits the active workout start event so the iPhone app can re-attach after a stale request.
    private func resendActiveWorkoutStartToCompanion() {
        guard jumpState == .jumping, let startTime else { return }

        let payload = MirroredWorkoutPayload(
            kind: .started,
            startTime: startTime,
            goalType: goalType,
            goalValue: goal,
            jumpCount: jumpCount,
            energyBurned: energyBurned,
            heartRate: heartrate > 0 ? heartrate : nil,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue
        )
        ConnectivityManager.shared.sendWorkoutEvent(payload)
        motionManager?.resendStartedEvent(payload)
    }

    /// Captures the observable Watch settings object into a plain value snapshot.
    private static func storedSettings(from settings: JumpRecSettings) -> StoredWorkoutSettings {
        StoredWorkoutSettings(
            goalType: settings.goalType,
            goalCount: settings.goalCount,
            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage,
            isQuotaExceeded: settings.isQuotaExceeded
        )
    }

    /// Applies synced settings without resetting HealthKit collection or jump history.
    func applyActiveSessionSettings(
        goalType: GoalType,
        goalCount: Int,
        shouldSpeakJumpCountAnnouncements: Bool,
        shouldSpeakJumpTimeAnnouncements: Bool,
        jumpDetectorThresholdAdjustmentPercentage: Double
    ) {
        guard jumpState == .jumping else { return }

        self.goalType = goalType
        sessionShouldSpeakJumpCountAnnouncements = shouldSpeakJumpCountAnnouncements
        sessionShouldSpeakJumpTimeAnnouncements = shouldSpeakJumpTimeAnnouncements
        switch goalType {
        case .count:
            goal = goalCount
        case .time:
            goal = goalCount * 60
        @unknown default:
            goal = goalCount
        }
        motionManager?.updateThresholdAdjustmentPercentage(jumpDetectorThresholdAdjustmentPercentage)
        endIfUpdatedGoalIsReached()
    }

    /// Ends the current workout if the newly edited goal is already satisfied.
    private func endIfUpdatedGoalIsReached() {
        guard jumpState == .jumping else { return }

        switch goalType {
        case .count:
            if jumpCount >= goal {
                end(reason: .goalReached)
            }
        case .time:
            guard let startTime else { return }
            if Int(Date().timeIntervalSince(startTime)) >= goal {
                end(reason: .goalReached)
            }
        @unknown default:
            break
        }
    }

    /// Ends the current watch workout and sends the finalized results to the phone.
    func end(reason: SessionEndReason) {
        guard jumpState == .jumping else { return }
        cancelMinuteAnnouncements()

        motionManager?.stopTracking()
        #if DEBUG
            let motionSamples = motionManager?.consumeRecordedSamples() ?? []
        #endif
        endTime = Date()
        let doubleUndersCount = motionManager?.doubleUndersCount
            ?? SessionMetricsCalculator.doubleUndersCount(from: jumps)
        WKInterfaceDevice.current().play(.stop)
        if let announcement = localizedSessionEndedAnnouncement(for: reason) {
            speak(text: announcement, interruptsCurrentSpeech: true)
        } else {
            stopSpeechAndDeactivateAudio()
        }
        ConnectivityManager.shared.sendWorkoutEvent(
            MirroredWorkoutPayload(
                kind: .ended,
                startTime: startTime,
                endTime: endTime,
                doubleUndersCount: doubleUndersCount
            )
        )

        jumpState = .finished

        guard let startTime, let endTime else { return }
        ConnectivityManager.shared.sendCompletedSession(
            startedAt: startTime,
            endedAt: endTime,
            jumpCount: jumpCount,
            caloriesBurned: energyBurned,
            jumpOffsets: jumps,
            doubleUndersCount: doubleUndersCount,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue,
            goalType: goalType
        )
        #if DEBUG
            exportMotionCSVIfNeeded(samples: motionSamples, startedAt: startTime, endedAt: endTime)
        #endif

        print("end finished")
    }

    /// Resets the watch app back to the idle state.
    func reset() {
        cancelPendingStart(notifyCompanion: true)
        showPermissionError = false
        showQuotaExplanation = false
        stopSpeechAndDeactivateAudio()
        cancelMinuteAnnouncements()
        motionManager?.stopTracking()
        #if DEBUG
            _ = motionManager?.consumeRecordedSamples()
        #endif
        resetSessionMetrics()
        jumpState = .idle
    }

    #if DEBUG
        /// Formats and sends recorded watch motion samples to the companion iPhone app.
        private func exportMotionCSVIfNeeded(samples: [MotionSample], startedAt: Date, endedAt: Date) {
            guard !samples.isEmpty else { return }

            let csvText = MotionCSVFormatter.makeCSV(from: samples)
            let filename = MotionCSVFormatter.makeFilename(prefix: "watch-motion", startedAt: startedAt, endedAt: endedAt)
            ConnectivityManager.shared.sendMotionCSV(csvText, filename: filename, startedAt: startedAt)
        }
    #endif

    // MARK: - Goal Tracking

    /// Adds newly detected jumps to the active session using the sensor-derived offset.
    func addJump(by: Int, jumpOffset: TimeInterval) {
        guard jumpState == .jumping, startTime != nil else { return }
        let before = jumpCount
        jumpCount += by
        jumps.append(jumpOffset)
        motionManager?.recordJump(jumpCount: jumpCount, jumpOffset: jumpOffset)
        checkJumpLandmark(before: before, after: jumpCount)
    }

    /// Handles count-based milestones and goal completion.
    func checkJumpLandmark(before: Int, after: Int) {
        // Count goals finish at the target; both goal types announce 100-jump milestones.
        if goalType == .count, jumpCount >= goal {
            end(reason: .goalReached)
            return
        }
        if before / 100 != after / 100 {
            handleHundredJumpsLandmark(jumpCount: jumpCount)
        }
    }

    /// Announces each 100-jump landmark during count-based sessions.
    func handleHundredJumpsLandmark(jumpCount: Int) {
        // Skip both haptics and speech when count cues are disabled.
        guard sessionShouldSpeakJumpCountAnnouncements else { return }

        WKInterfaceDevice.current().play(.success)
        let hundred = jumpCount / 100 * 100
        speak(text: localizedJumpAnnouncement(for: hundred))
    }

    /// Starts cancellable structured-concurrency work for minute announcements.
    func startMinuteAnnouncements() {
        cancelMinuteAnnouncements()
        minuteAnnouncementTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    // Sleep between minute cues without blocking the main actor.
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

    /// Cancels pending minute-announcement work for the current workout.
    func cancelMinuteAnnouncements() {
        minuteAnnouncementTask?.cancel()
        minuteAnnouncementTask = nil
    }

    /// Announces elapsed minutes for every session and ends timed sessions when needed.
    private func handleMinuteLandmark() {
        guard jumpState == .jumping, let startTime else { return }
        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        if minutesElapsed <= 0 { return }
        if goalType == .time, minutesElapsed * 60 >= goal {
            end(reason: .goalReached)
            return
        }

        // Skip disabled minute cues while retaining time-goal completion.
        guard sessionShouldSpeakJumpTimeAnnouncements else { return }

        speak(text: localizedMinuteAnnouncement(for: minutesElapsed))
        WKInterfaceDevice.current().play(.success)
    }

    /// Clears the live metrics stored for the current session.
    func resetSessionMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        heartrate = 0
        heartRateSum = 0
        heartRateSampleCount = 0
        peakHeartRate = 0
        energyBurned = 0
        endTime = nil
        startTime = nil
    }
}
