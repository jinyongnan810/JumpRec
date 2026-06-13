//
//  AppState+SessionLifecycle.swift
//  JumpRec
//

import Foundation
import WatchKit

extension JumpRecState {
    // MARK: - Session Lifecycle

    /// Starts a new watch-tracked workout session.
    func start(goalType: GoalType, goalCount: Int) {
        resetSessionMetrics()
        self.goalType = goalType
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
            motionManager?.startTracking(startDate: startTime, goalType: goalType, goalValue: goal)
        }
        jumpState = .jumping
        // Start minute announcements for every workout so elapsed-time feedback
        // remains available even when the user selected a jump-count goal.
        startMinuteAnnouncements()
        WKInterfaceDevice.current().play(.start)
        speak(text: localizedSessionStartedAnnouncement)
        ConnectivityManager.shared.sendMessage(["watch app": "started"])
    }

    /// Starts a workout using settings received from the companion iPhone app.
    func startFromCompanion() {
        let settings = JumpRecSettings()
        settings.loadSettings()
        start(goalType: settings.goalType, goalCount: settings.goalCount)
    }

    /// Ends the current watch workout and sends the finalized results to the phone.
    func end() {
        guard jumpState == .jumping else { return }
        cancelMinuteAnnouncements()

        motionManager?.stopTracking()
        endTime = Date()
        speak(text: localizedSessionFinishedAnnouncement, delay: 0.5)
        WKInterfaceDevice.current().play(.stop)
        ConnectivityManager.shared.sendMessage(["watch app": "finished"])

        jumpState = .finished

        guard let startTime, let endTime else { return }
        ConnectivityManager.shared.sendCompletedSession(
            startedAt: startTime,
            endedAt: endTime,
            jumpCount: jumpCount,
            caloriesBurned: energyBurned,
            jumpOffsets: jumps,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue
        )

        print("end finished")
    }

    /// Resets the watch app back to the idle state.
    func reset() {
        cancelMinuteAnnouncements()
        motionManager?.stopTracking()
        resetSessionMetrics()
        jumpState = .idle
    }

    // MARK: - Goal Tracking

    /// Adds newly detected jumps to the active session.
    func addJump(by: Int) {
        guard jumpState == .jumping, let startTime else { return }
        let before = jumpCount
        jumpCount += by
        let jumpOffset = Date().timeIntervalSince(startTime)
        jumps.append(jumpOffset)
        motionManager?.recordJump(jumpCount: jumpCount, jumpOffset: jumpOffset)
        checkJumpLandmark(before: before, after: jumpCount)
    }

    /// Handles count-based milestones and goal completion.
    func checkJumpLandmark(before: Int, after: Int) {
        // Only count-goal sessions should auto-finish from jump progress, but the
        // 100-jump announcement should fire in both goal modes so watch feedback
        // matches the phone experience.
        if goalType == .count, jumpCount >= goal {
            end()
            return
        }
        if before / 100 != after / 100 {
            handleHundredJumpsLandmark(jumpCount: jumpCount)
        }
    }

    /// Announces each 100-jump landmark during count-based sessions.
    func handleHundredJumpsLandmark(jumpCount: Int) {
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
                    // Suspending avoids blocking the main actor and removes the need to
                    // force-unwrap a timer before adding it to the watch run loop.
                    try await Task.sleep(for: .seconds(60))
                } catch is CancellationError {
                    return
                } catch {
                    // `Task.sleep` currently only throws for cancellation. Returning for
                    // any future error keeps this repeating task from spinning rapidly.
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
            end()
            return
        }
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
