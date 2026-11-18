//
//  JumpDetector.swift
//  JumpRec
//
//  Created by kinn on 2026/02/28.
//

import Foundation

public nonisolated enum JumpDeviceProfile: String, Sendable {
    case headphones
    case watch
}

public nonisolated enum JumpDetectorAxis: String, Sendable {
    case x
    case y
    case z
}

public nonisolated enum JumpDetectorPolarity: String, Sendable {
    case positivePeak
    case negativeTrough
}

public final nonisolated class JumpDetector {
    // MARK: - Configuration

    /// Signal, threshold, and timing settings for a device profile.
    private struct Config {
        /// The device profile this config belongs to.
        let profile: JumpDeviceProfile
        /// Raw motion signal axis evaluated for jump detection.
        let axis: JumpDetectorAxis
        /// The extremum direction that represents a jump on the selected signal.
        let polarity: JumpDetectorPolarity
        /// Baseline acceleration threshold scaled by the user's percentage adjustment.
        let threshold: Double
        /// Signal level that must be crossed in the opposite direction to re-arm detection.
        let rearmThreshold: Double
        /// Minimum time between accepted jumps to prevent double counting.
        let minimumInterval: TimeInterval

        static func profile(_ profile: JumpDeviceProfile) -> Config {
            switch profile {
            case .headphones:
                Config(
                    profile: .headphones,
                    axis: .z,
                    polarity: .negativeTrough,
                    threshold: -1.2,
                    rearmThreshold: 0.1,
                    minimumInterval: 0.1
                )
            case .watch:
                Config(
                    profile: .watch,
                    axis: .z,
                    polarity: .positivePeak,
                    threshold: 0.8,
                    rearmThreshold: -0.1,
                    minimumInterval: 0.1
                )
            }
        }
    }

    private static let watchDoubleUnderMinimumInterval: TimeInterval = 0.16
    private static let watchDoubleUnderMaximumInterval: TimeInterval = 0.33
    private static let watchDoubleUnderFirstTurnMinimumPeak: Double = 5.0
    private static let watchDoubleUnderFirstTurnMaximumTrough: Double = -4.0
    private static let watchDoubleUnderMinimumPeakToPeak: Double = 9.5
    private static let watchDoubleUnderSecondTurnMinimumPeak: Double = 2.5

    // MARK: - Public State

    /// The public profile exposed to callers and debug tooling.
    public let profile: JumpDeviceProfile
    /// Optional console logging for debugging live sessions.
    public var debugLoggingEnabled = false
    /// Number of sensor-confirmed double-unders detected in the current Watch session.
    public private(set) var doubleUndersCount = 0

    // MARK: - Private State

    /// The fixed profile rule used by this detector instance.
    private let config: Config
    /// Signed threshold adjustment from -50% to 50%; +50% scales -1.2 to -1.8.
    private var thresholdAdjustmentPercentage: Double
    /// Cached threshold for frequent motion-sample comparisons.
    private var adjustedThreshold: Double
    /// Whether the signal has returned past the re-arm threshold since the last accepted jump.
    private var canDetectNextJump = true
    /// Timestamp of the last jump that passed threshold and refractory checks.
    private var lastAcceptedJumpTimestamp: TimeInterval?
    /// Whether at least one Watch rope turn has been observed in the current session.
    private var hasTrackedWatchTurn = false
    /// Trigger timestamp of the most recent Watch turn.
    private var activeWatchTurnTimestamp: TimeInterval = 0
    /// Peak Z acceleration observed during the active Watch turn.
    private var activeWatchTurnMaxValue: Double = 0
    /// Minimum Z acceleration observed after the active Watch turn re-armed.
    private var activeWatchTurnMinValue: Double = 0
    /// Prevents a Watch turn that completed a double-under from starting another pair.
    private var isActiveWatchTurnConsumedForDoubleUnder = false
    /// Indicates whether the active Watch turn can confirm a double-under once its peak qualifies.
    private var isPendingSecondWatchDoubleUnderTurn = false

    // MARK: - Initialization

    /// Creates a detector for a profile with a threshold adjustment from -50% to 50%.
    public init(profile: JumpDeviceProfile = .headphones, thresholdAdjustmentPercentage: Double = 0) {
        self.profile = profile
        config = .profile(profile)
        self.thresholdAdjustmentPercentage = Self.clampedThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
        adjustedThreshold = Self.adjustedThreshold(
            baseThreshold: config.threshold,
            adjustmentPercentage: self.thresholdAdjustmentPercentage
        )
    }

    // MARK: - Public Methods

    /// Changes sensitivity for future samples without resetting detection timing.
    public func updateThresholdAdjustmentPercentage(_ percentage: Double) {
        thresholdAdjustmentPercentage = Self.clampedThresholdAdjustmentPercentage(percentage)
        adjustedThreshold = Self.adjustedThreshold(
            baseThreshold: config.threshold,
            adjustmentPercentage: thresholdAdjustmentPercentage
        )
    }

    /// Checks one motion sample against the profile's signal, re-arm level, and threshold.
    public func processMotionSample(_ sample: MotionSample) -> Bool {
        let value = axisValue(from: sample, axis: config.axis)

        if !canDetectNextJump {
            if profile == .watch {
                updateActiveWatchTurnPeak(with: value)
            }
            guard rearmSatisfied(value: value) else {
                return false
            }
            canDetectNextJump = true
        }

        if profile == .watch {
            updateActiveWatchTurnTrough(with: value)
        }

        let isCandidate = thresholdSatisfied(value: value)

        guard isCandidate else {
            return false
        }

        if let lastAcceptedJumpTimestamp,
           sample.timestamp - lastAcceptedJumpTimestamp < config.minimumInterval
        {
            return false
        }

        canDetectNextJump = false
        lastAcceptedJumpTimestamp = sample.timestamp
        if profile == .watch {
            beginWatchTurn(at: sample.timestamp, initialValue: value)
        }

        if debugLoggingEnabled {
            print(
                "[JumpDetector] profile=\(profile.rawValue) axis=\(config.axis.rawValue) " +
                    "polarity=\(config.polarity.rawValue) value=\(value) accepted=\(sample.timestamp)"
            )
        }

        return true
    }

    /// Clears the refractory and re-arm state so a new session starts fresh.
    public func reset() {
        canDetectNextJump = true
        lastAcceptedJumpTimestamp = nil
        doubleUndersCount = 0
        hasTrackedWatchTurn = false
        activeWatchTurnTimestamp = 0
        activeWatchTurnMaxValue = 0
        activeWatchTurnMinValue = 0
        isActiveWatchTurnConsumedForDoubleUnder = false
        isPendingSecondWatchDoubleUnderTurn = false
    }

    // MARK: - Private Helpers

    /// Multiplier that scales Watch amplitude thresholds in proportion to user sensitivity tuning.
    private var sensitivityScale: Double {
        1 + (thresholdAdjustmentPercentage / 100)
    }

    /// Updates the peak acceleration of the current Watch turn and confirms a pending double-under.
    private func updateActiveWatchTurnPeak(with value: Double) {
        guard hasTrackedWatchTurn, value > activeWatchTurnMaxValue else { return }
        activeWatchTurnMaxValue = value
        confirmPendingWatchDoubleUnderIfNeeded()
    }

    /// Tracks the negative whip trough reached after the active Watch turn re-arms.
    private func updateActiveWatchTurnTrough(with value: Double) {
        guard hasTrackedWatchTurn, value < activeWatchTurnMinValue else { return }
        activeWatchTurnMinValue = value
    }

    /// Starts tracking a newly accepted Watch turn and evaluates whether it pairs with the prior turn.
    private func beginWatchTurn(at timestamp: TimeInterval, initialValue: Double) {
        let scale = sensitivityScale
        let shouldStartPendingSecondTurn: Bool
        if hasTrackedWatchTurn, !isActiveWatchTurnConsumedForDoubleUnder {
            let interval = timestamp - activeWatchTurnTimestamp
            let peakToPeak = activeWatchTurnMaxValue - activeWatchTurnMinValue
            shouldStartPendingSecondTurn =
                interval >= Self.watchDoubleUnderMinimumInterval &&
                interval <= Self.watchDoubleUnderMaximumInterval &&
                activeWatchTurnMaxValue >= Self.watchDoubleUnderFirstTurnMinimumPeak * scale &&
                activeWatchTurnMinValue <= Self.watchDoubleUnderFirstTurnMaximumTrough * scale &&
                peakToPeak >= Self.watchDoubleUnderMinimumPeakToPeak * scale
        } else {
            shouldStartPendingSecondTurn = false
        }

        hasTrackedWatchTurn = true
        activeWatchTurnTimestamp = timestamp
        activeWatchTurnMaxValue = initialValue
        activeWatchTurnMinValue = 0
        isActiveWatchTurnConsumedForDoubleUnder = false
        isPendingSecondWatchDoubleUnderTurn = shouldStartPendingSecondTurn
        confirmPendingWatchDoubleUnderIfNeeded()
    }

    /// Confirms a pending double-under once the second turn reaches the required acceleration peak.
    private func confirmPendingWatchDoubleUnderIfNeeded() {
        guard isPendingSecondWatchDoubleUnderTurn,
              activeWatchTurnMaxValue >= Self.watchDoubleUnderSecondTurnMinimumPeak * sensitivityScale
        else {
            return
        }

        doubleUndersCount += 1
        isPendingSecondWatchDoubleUnderTurn = false
        isActiveWatchTurnConsumedForDoubleUnder = true
    }

    /// Reads the requested raw acceleration signal from a sample.
    private func axisValue(from sample: MotionSample, axis: JumpDetectorAxis) -> Double {
        switch axis {
        case .x:
            sample.userAccelerationX
        case .y:
            sample.userAccelerationY
        case .z:
            sample.userAccelerationZ
        }
    }

    /// Applies the cached threshold rule for the active profile.
    private func thresholdSatisfied(value: Double) -> Bool {
        switch config.polarity {
        case .positivePeak:
            value > adjustedThreshold
        case .negativeTrough:
            value < adjustedThreshold
        }
    }

    /// Returns whether the signal has crossed back past the profile's re-arm threshold.
    private func rearmSatisfied(value: Double) -> Bool {
        switch config.polarity {
        case .positivePeak:
            value <= config.rearmThreshold
        case .negativeTrough:
            value >= config.rearmThreshold
        }
    }

    /// Calculates the signed threshold once whenever user tuning changes.
    private static func adjustedThreshold(baseThreshold: Double, adjustmentPercentage: Double) -> Double {
        baseThreshold * (1 + (adjustmentPercentage / 100))
    }

    /// Restricts sensitivity tuning to the supported settings range.
    private static func clampedThresholdAdjustmentPercentage(_ percentage: Double) -> Double {
        min(50, max(-50, percentage))
    }
}
