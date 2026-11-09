//
//  JumpDetector.swift
//  JumpRec
//
//  Created by kinn on 2026/02/28.
//

import Foundation

public enum JumpDeviceProfile: String, Sendable {
    case headphones
    case watch
}

public enum JumpDetectorAxis: String, Sendable {
    case x
    case y
    case z
}

public enum JumpDetectorPolarity: String, Sendable {
    case positivePeak
    case negativeTrough
}

public final class JumpDetector {
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

    // MARK: - Public State

    /// The public profile exposed to callers and debug tooling.
    public let profile: JumpDeviceProfile
    /// Optional console logging for debugging live sessions.
    public var debugLoggingEnabled = false

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
            guard rearmSatisfied(value: value) else {
                return false
            }
            canDetectNextJump = true
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
    }

    // MARK: - Private Helpers

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
