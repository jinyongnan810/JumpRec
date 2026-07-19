//
//  JumpDetector.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/28.
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
    /// Reserved for compatibility with the previous detector design. Always `false` here.
    public let rhythmLocked: Bool
    /// Reserved for compatibility with the previous detector design. Always `nil` here.
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

    /// A tiny profile config for the intentionally simple detector.
    private struct Config {
        /// The device profile this config belongs to.
        let profile: JumpDeviceProfile
        /// The raw `MotionSample` signal to inspect.
        ///
        /// Axis values are useful when a device has a predictable placement, while `.magnitude`
        /// keeps detection independent from how the user rotates or holds the device.
        let axis: JumpDetectorAxis
        /// The extremum direction that represents a jump on the selected signal.
        let polarity: JumpDetectorPolarity
        /// The default raw acceleration threshold that must be crossed to count a jump.
        ///
        /// User tuning is applied as a percentage of this baseline so profile calibration
        /// stays centralized here while settings only store a relative adjustment.
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
    /// User-selected percentage applied to the profile's default threshold.
    ///
    /// The stored value is a real percentage from `-50` to `50`. Applying it to the
    /// signed threshold keeps negative troughs intuitive: `50%` turns `-1.2` into
    /// `-1.8`, which requires a deeper negative motion event.
    private var thresholdAdjustmentPercentage: Double
    /// Cached threshold used by the hot sample-processing path.
    ///
    /// Motion samples arrive many times per second, while settings change rarely.
    /// Caching keeps `thresholdSatisfied(value:)` to a direct comparison even when
    /// the active-session settings sheet updates the threshold during a workout.
    private var adjustedThreshold: Double
    /// Timestamp of the last jump that passed threshold and refractory checks.
    private var lastAcceptedJumpTimestamp: TimeInterval?

    // MARK: - Initialization

    /// Creates a detector configured for the specified device profile.
    /// - Parameters:
    ///   - profile: The device profile whose axis, polarity, and baseline threshold should be used.
    ///   - thresholdAdjustmentPercentage: A relative threshold adjustment from `-50` to `50`.
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

    /// Updates the relative threshold adjustment used for subsequent samples.
    ///
    /// Callers use this at session start and when the active-session settings sheet changes sensitivity.
    /// The update affects future samples without clearing the detector's timing state.
    public func updateThresholdAdjustmentPercentage(_ percentage: Double) {
        thresholdAdjustmentPercentage = Self.clampedThresholdAdjustmentPercentage(percentage)
        adjustedThreshold = Self.adjustedThreshold(
            baseThreshold: config.threshold,
            adjustmentPercentage: thresholdAdjustmentPercentage
        )
    }

    /// Processes one raw motion sample.
    /// The detector inspects the configured raw acceleration signal and threshold for the profile.
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

    /// Keeps debug state aligned with the simple detector implementation.
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
