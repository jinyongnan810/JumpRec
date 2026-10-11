//
//  JumpDetector.swift
//  JumpRec
//
//  Created by kinn on 2026/02/28.
//

import Foundation

public enum JumpDeviceProfile: String, Sendable {
    case iPhonePocket
    case headphones
    case watch
}

public enum JumpDetectorAxis: String, Sendable {
    case x
    case y
    case z
    case magnitude
}

public enum JumpDetectorPolarity: String, Sendable {
    case positivePeak
    case negativeTrough
    case positiveMagnitude
}

public struct JumpDetectorDebugState: Sendable {
    /// The profile currently used by this detector instance.
    public let profile: JumpDeviceProfile
    /// The single axis being evaluated for the active profile.
    public let dominantAxis: JumpDetectorAxis?
    /// Whether the detector is looking for a positive peak or negative trough.
    public let chosenPolarity: JumpDetectorPolarity?
    /// Unused by this detector; always false.
    public let rhythmLocked: Bool
    /// Unused by this detector; always nil.
    public let expectedInterval: TimeInterval?
    /// Timestamp of the last accepted jump after refractory filtering.
    public let lastAcceptedJumpTimestamp: TimeInterval?

    public init(
        profile: JumpDeviceProfile,
        dominantAxis: JumpDetectorAxis? = nil,
        chosenPolarity: JumpDetectorPolarity? = nil,
        rhythmLocked: Bool = false,
        expectedInterval: TimeInterval? = nil,
        lastAcceptedJumpTimestamp: TimeInterval? = nil
    ) {
        self.profile = profile
        self.dominantAxis = dominantAxis
        self.chosenPolarity = chosenPolarity
        self.rhythmLocked = rhythmLocked
        self.expectedInterval = expectedInterval
        self.lastAcceptedJumpTimestamp = lastAcceptedJumpTimestamp
    }
}

public final class JumpDetector {
    // MARK: - Configuration

    /// Signal, threshold, and timing settings for a device profile.
    private struct Config {
        /// The device profile this config belongs to.
        let profile: JumpDeviceProfile
        /// Raw motion signal; magnitude is independent of device orientation.
        let axis: JumpDetectorAxis
        /// The extremum direction that represents a jump on the selected signal.
        let polarity: JumpDetectorPolarity
        /// Baseline acceleration threshold scaled by the user's percentage adjustment.
        let threshold: Double
        /// Minimum time between accepted jumps to prevent double counting.
        let minimumInterval: TimeInterval

        static func profile(_ profile: JumpDeviceProfile) -> Config {
            switch profile {
            case .iPhonePocket:
                Config(
                    profile: .iPhonePocket,
                    axis: .magnitude,
                    polarity: .positiveMagnitude,
                    threshold: 1.2,
                    minimumInterval: 0.25
                )
            case .headphones:
                Config(
                    profile: .headphones,
                    axis: .z,
                    polarity: .negativeTrough,
                    threshold: -1.2,
                    minimumInterval: 0.25
                )
            case .watch:
                Config(
                    profile: .watch,
                    axis: .y,
                    polarity: .positivePeak,
                    threshold: 0.8,
                    minimumInterval: 0.25
                )
            }
        }
    }

    // MARK: - Public State

    /// The public profile exposed to callers and debug tooling.
    public let profile: JumpDeviceProfile
    /// Optional console logging for debugging live sessions.
    public var debugLoggingEnabled = false
    /// Snapshot of the detector state used by debugging and inspection.
    public private(set) var debugState: JumpDetectorDebugState

    // MARK: - Private State

    /// The fixed profile rule used by this detector instance.
    private let config: Config
    /// Signed threshold adjustment from -50% to 50%; +50% scales -1.2 to -1.8.
    private var thresholdAdjustmentPercentage: Double
    /// Cached threshold for frequent motion-sample comparisons.
    private var adjustedThreshold: Double
    /// Timestamp of the last jump that passed threshold and refractory checks.
    private var lastAcceptedJumpTimestamp: TimeInterval?

    // MARK: - Initialization

    /// Creates a detector for a profile with a threshold adjustment from -50% to 50%.
    public init(profile: JumpDeviceProfile = .iPhonePocket, thresholdAdjustmentPercentage: Double = 0) {
        self.profile = profile
        config = .profile(profile)
        self.thresholdAdjustmentPercentage = Self.clampedThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
        adjustedThreshold = Self.adjustedThreshold(
            baseThreshold: config.threshold,
            adjustmentPercentage: self.thresholdAdjustmentPercentage
        )
        debugState = JumpDetectorDebugState(
            profile: profile,
            dominantAxis: config.axis,
            chosenPolarity: config.polarity
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

    /// Checks one motion sample against the profile's signal and threshold.
    public func processMotionSample(_ sample: MotionSample) -> Bool {
        let value = axisValue(from: sample, axis: config.axis)
        let isCandidate = thresholdSatisfied(value: value)

        guard isCandidate else {
            syncDebugState()
            return false
        }

        if let lastAcceptedJumpTimestamp,
           sample.timestamp - lastAcceptedJumpTimestamp < config.minimumInterval
        {
            syncDebugState()
            return false
        }

        lastAcceptedJumpTimestamp = sample.timestamp
        syncDebugState()

        if debugLoggingEnabled {
            print(
                "[JumpDetector] profile=\(profile.rawValue) axis=\(config.axis.rawValue) " +
                    "polarity=\(config.polarity.rawValue) value=\(value) accepted=\(sample.timestamp)"
            )
        }

        return true
    }

    /// Clears the simple refractory state so a new session starts fresh.
    public func reset() {
        lastAcceptedJumpTimestamp = nil
        syncDebugState()
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
        case .magnitude:
            sqrt(
                (sample.userAccelerationX * sample.userAccelerationX) +
                    (sample.userAccelerationY * sample.userAccelerationY) +
                    (sample.userAccelerationZ * sample.userAccelerationZ)
            )
        }
    }

    /// Applies the cached threshold rule for the active profile.
    private func thresholdSatisfied(value: Double) -> Bool {
        switch config.polarity {
        case .positivePeak, .positiveMagnitude:
            value > adjustedThreshold
        case .negativeTrough:
            value < adjustedThreshold
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

    /// Updates debug state to match the active detector.
    private func syncDebugState() {
        debugState = JumpDetectorDebugState(
            profile: profile,
            dominantAxis: config.axis,
            chosenPolarity: config.polarity,
            rhythmLocked: false,
            expectedInterval: nil,
            lastAcceptedJumpTimestamp: lastAcceptedJumpTimestamp
        )
    }
}
