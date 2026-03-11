//
//  AppState.swift
//  JumpRec
//

import Foundation
import JumpRecShared
import Observation

@Observable
@MainActor
final class JumpRecState {
    var sessionState: SessionState = .idle
    var startTime: Date?
    var endTime: Date?
    var jumpCount = 0
    var jumps: [TimeInterval] = []
    var caloriesBurned = 0.0
    var averageHeartRate: Int?
    var peakHeartRate: Int?
    var sessionGoalType: GoalType?
    var sessionGoalValue: Int?
    var isMirroredWatchSession = false

    var activeMotionSource: DeviceSource?
    var isPhoneMotionAvailable = false
    var isHeadphoneMotionAvailable = false

    @ObservationIgnored
    let dataStore = MyDataStore.shared

    @ObservationIgnored
    private var motionManager: MotionManager?
    @ObservationIgnored
    private let workoutMirrorManager = WorkoutMirrorManager.shared
    @ObservationIgnored
    private let connectivityManager = ConnectivityManager.shared

    init() {
        motionManager = MotionManager(
            onJumpDetected: { [weak self] source in
                self?.addJump(from: source)
            },
            onSourceChanged: { [weak self] source in
                self?.activeMotionSource = Self.deviceSource(from: source)
            },
            onAvailabilityChanged: { [weak self] isPhoneAvailable, isHeadphoneAvailable in
                self?.isPhoneMotionAvailable = isPhoneAvailable
                self?.isHeadphoneMotionAvailable = isHeadphoneAvailable
            }
        )
        motionManager?.refreshAvailability()
        workoutMirrorManager.onPayloadReceived = { [weak self] payload in
            self?.handleMirroredWorkoutPayload(payload)
        }
        workoutMirrorManager.onMirroredSessionEnded = { [weak self] in
            self?.handleMirroredSessionEnded()
        }
        connectivityManager.onCompletedSessionReceived = { [weak self] startedAt, endedAt, jumpCount, caloriesBurned, jumpOffsets, averageHeartRate, peakHeartRate in
            self?.applyCompletedWatchSession(
                startedAt: startedAt,
                endedAt: endedAt,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumpOffsets,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )
        }
    }

    var durationSeconds: Int {
        guard let startTime else { return 0 }
        let end = endTime ?? Date()
        return max(0, Int(end.timeIntervalSince(startTime)))
    }

    var elapsedFormatted: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    var averageRate: Int {
        guard durationSeconds > 0 else { return 0 }
        return Int((Double(jumpCount) * 60.0 / Double(durationSeconds)).rounded())
    }

    var breakMetrics: (small: Int, long: Int, longestStreak: Int) {
        SessionMetricsCalculator.breakMetrics(from: jumps)
    }

    func start() {
        resetLiveMetrics()
        startTime = Date()
        endTime = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = nil
        sessionGoalValue = nil
        isMirroredWatchSession = false
        sessionState = .active
        motionManager?.startTracking()
    }

    func finish() {
        guard sessionState == .active, let startTime else { return }
        guard !isMirroredWatchSession else { return }

        motionManager?.stopTracking()
        endTime = Date()
        sessionState = .complete

        if let endTime {
            dataStore.saveCompletedSession(
                startedAt: startTime,
                endedAt: endTime,
                jumpCount: jumpCount,
                caloriesBurned: caloriesBurned,
                jumpOffsets: jumps
            )
        }
    }

    func reset() {
        motionManager?.stopTracking()
        sessionState = .idle
        resetLiveMetrics()
        activeMotionSource = nil
        averageHeartRate = nil
        peakHeartRate = nil
        sessionGoalType = nil
        sessionGoalValue = nil
        isMirroredWatchSession = false
    }

    private func addJump(from source: MotionManager.Source) {
        guard sessionState == .active, let startTime else { return }

        let resolvedSource = Self.deviceSource(from: source)
        if activeMotionSource == .airpods, resolvedSource == .iPhone {
            return
        }

        activeMotionSource = resolvedSource
        jumpCount += 1
        jumps.append(Date().timeIntervalSince(startTime))
    }

    private func resetLiveMetrics() {
        jumpCount = 0
        jumps.removeAll(keepingCapacity: true)
        caloriesBurned = 0
        startTime = nil
        endTime = nil
    }

    private func handleMirroredWorkoutPayload(_ payload: MirroredWorkoutPayload) {
        switch payload.kind {
        case .started:
            beginMirroredSession(payload)
        case .jump:
            applyMirroredJump(payload)
        case .metrics:
            applyMirroredMetrics(payload)
        case .ended:
            applyMirroredEnding(payload)
        }
    }

    private func beginMirroredSession(_ payload: MirroredWorkoutPayload) {
        resetLiveMetrics()
        averageHeartRate = nil
        peakHeartRate = nil
        startTime = payload.startTime ?? Date()
        endTime = nil
        jumpCount = payload.jumpCount ?? 0
        sessionGoalType = payload.goalType
        sessionGoalValue = payload.goalValue
        sessionState = .active
        isMirroredWatchSession = true
        activeMotionSource = .watch
    }

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
    }

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
    }

    private func applyMirroredEnding(_ payload: MirroredWorkoutPayload) {
        guard isMirroredWatchSession else { return }

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
    }

    private func handleMirroredSessionEnded() {
        guard isMirroredWatchSession, sessionState == .active else { return }
        endTime = endTime ?? Date()
        sessionState = .complete
    }

    private func applyCompletedWatchSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int?,
        peakHeartRate: Int?
    ) {
        guard isMirroredWatchSession else { return }

        startTime = startedAt
        endTime = endedAt
        self.jumpCount = jumpCount
        jumps = jumpOffsets
        self.caloriesBurned = caloriesBurned
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        sessionState = .complete
    }

    private static func deviceSource(from source: MotionManager.Source?) -> DeviceSource? {
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
