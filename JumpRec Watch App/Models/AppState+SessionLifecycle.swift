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
        if goalType == .time {
            startMinuteTimer()
        }
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

    /// Ends the current watch workout, saves it, and sends results to the phone.
    func end() {
        guard jumpState == .jumping else { return }
        invalidateMinuteTimer()

        motionManager?.stopTracking()
        endTime = Date()
        speak(text: localizedSessionFinishedAnnouncement, delay: 0.5)
        WKInterfaceDevice.current().play(.stop)
        ConnectivityManager.shared.sendMessage(["watch app": "finished"])

        jumpState = .finished

        guard let startTime, let endTime else { return }
        dataStore.saveCompletedSession(
            startedAt: startTime,
            endedAt: endTime,
            jumpCount: jumpCount,
            caloriesBurned: energyBurned,
            jumpOffsets: jumps,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRateValue
        )

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
        invalidateMinuteTimer()
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
        if goalType == .time {
            return
        }
        if jumpCount >= goal {
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

    /// Starts the timer used for minute-based announcements.
    func startMinuteTimer() {
        invalidateMinuteTimer()
        minuteTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleMinuteLandmark()
            }
        }
        RunLoop.current.add(minuteTimer!, forMode: .common)
    }

    /// Invalidates the active minute timer.
    func invalidateMinuteTimer() {
        minuteTimer?.invalidate()
        minuteTimer = nil
    }

    /// Announces elapsed minutes and ends the session when the time goal is met.
    private func handleMinuteLandmark() {
        guard jumpState == .jumping, goalType == .time, let startTime else { return }
        let minutesElapsed = Int(Date().timeIntervalSince(startTime)) / 60
        if minutesElapsed <= 0 { return }
        if minutesElapsed * 60 >= goal {
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
