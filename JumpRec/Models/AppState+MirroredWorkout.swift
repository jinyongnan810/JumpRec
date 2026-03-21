//
//  AppState+MirroredWorkout.swift
//  JumpRec
//

import Foundation

extension JumpRecState {
    // MARK: - Mirrored Workout Handling

    /// Routes an incoming mirrored payload to the correct handler.
    func handleMirroredWorkoutPayload(_ payload: MirroredWorkoutPayload) {
        switch payload.kind {
        case .started:
            beginMirroredSession(payload)
        case .jump:
            applyMirroredJump(payload)
        case .metrics:
            applyMirroredMetrics(payload)
        case .ended:
            applyMirroredEnding(payload)
        @unknown default:
            break
        }
    }

    /// Handles the mirrored session ending without a final payload.
    func handleMirroredSessionEnded() {
        guard isMirroredWatchSession, sessionState == .active else { return }
        invalidateMinuteTimer()
        endTime = endTime ?? Date()
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Applies a fully completed session received from the watch app.
    func applyCompletedWatchSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int?,
        peakHeartRate: Int?,
        session: JumpSession
    ) {
        guard isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        startTime = startedAt
        endTime = endedAt
        self.jumpCount = jumpCount
        jumps = jumpOffsets
        self.caloriesBurned = caloriesBurned
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        completedSession = session
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Initializes local mirrored-session state from a watch payload.
    private func beginMirroredSession(_ payload: MirroredWorkoutPayload) {
        invalidateMinuteTimer()
        pendingMirroredStart = false
        resetLiveMetrics()
        averageHeartRate = nil
        peakHeartRate = nil
        completedSession = nil
        startTime = payload.startTime ?? Date()
        endTime = nil
        jumpCount = payload.jumpCount ?? 0
        sessionGoalType = payload.goalType
        sessionGoalValue = normalizedGoalValue(payload.goalValue, for: payload.goalType)
        sessionState = .active
        isMirroredWatchSession = true
        activeMotionSource = .watch
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Applies mirrored jump updates from Apple Watch.
    private func applyMirroredJump(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        activeMotionSource = .watch
        if let jumpCount = payload.jumpCount {
            self.jumpCount = max(self.jumpCount, jumpCount)
        }
        if let jumpOffset = payload.jumpOffset {
            let shouldAppend = jumps.last.map { jumpOffset > $0 } ?? true
            if shouldAppend {
                jumps.append(jumpOffset)
            }
        }
        syncLiveActivity()
    }

    /// Applies mirrored heart-rate and calorie updates from Apple Watch.
    private func applyMirroredMetrics(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        if let energyBurned = payload.energyBurned {
            caloriesBurned = energyBurned
        }
        if let averageHeartRate = payload.averageHeartRate {
            self.averageHeartRate = averageHeartRate
        }
        if let peakHeartRate = payload.peakHeartRate {
            self.peakHeartRate = peakHeartRate
        }
        syncLiveActivity()
    }

    /// Applies the mirrored workout end state from Apple Watch.
    private func applyMirroredEnding(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

        invalidateMinuteTimer()
        endTime = payload.endTime ?? Date()
        if let energyBurned = payload.energyBurned {
            caloriesBurned = energyBurned
        }
        if let averageHeartRate = payload.averageHeartRate {
            self.averageHeartRate = averageHeartRate
        }
        if let peakHeartRate = payload.peakHeartRate {
            self.peakHeartRate = peakHeartRate
        }
        sessionState = .complete
        syncIdleTimer()
        syncLiveActivity()
    }

    /// Converts mirrored goal values into the units expected by the iPhone UI.
    private func normalizedGoalValue(_ goalValue: Int?, for goalType: GoalType?) -> Int? {
        guard let goalValue, let goalType else { return goalValue }

        switch goalType {
        case .count:
            return goalValue
        case .time:
            return goalValue / 60
        @unknown default:
            return goalValue
        }
    }
}
