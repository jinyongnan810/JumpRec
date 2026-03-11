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

    var activeMotionSource: DeviceSource?
    var isPhoneMotionAvailable = false
    var isHeadphoneMotionAvailable = false

    @ObservationIgnored
    let dataStore = MyDataStore.shared

    @ObservationIgnored
    private var motionManager: MotionManager?

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
        sessionState = .active
        motionManager?.startTracking()
    }

    func finish() {
        guard sessionState == .active, let startTime else { return }

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
