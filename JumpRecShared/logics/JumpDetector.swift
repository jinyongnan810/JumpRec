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
    /// A tiny profile config for the intentionally simple detector.
    private struct Config {
        /// The device profile this config belongs to.
        let profile: JumpDeviceProfile
        /// The raw `MotionSample` axis to inspect.
        let axis: JumpDetectorAxis
        /// The extremum direction that represents a jump on the selected axis.
        let polarity: JumpDetectorPolarity
        /// The raw acceleration threshold that must be crossed to count a jump.
        let threshold: Double
        /// Minimum time between accepted jumps to prevent double counting.
        let minimumInterval: TimeInterval

        static func profile(_ profile: JumpDeviceProfile) -> Config {
            switch profile {
            case .iPhonePocket:
                Config(
                    profile: .iPhonePocket,
                    axis: .y,
                    polarity: .positivePeak,
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

    /// The public profile exposed to callers and debug tooling.
    public let profile: JumpDeviceProfile
    /// Optional console logging for debugging live sessions.
    public var debugLoggingEnabled = false
    /// Snapshot of the detector state used by debugging and inspection.
    public private(set) var debugState: JumpDetectorDebugState

    /// The fixed threshold rule used by this detector instance.
    private let config: Config
    /// Timestamp of the last jump that passed threshold and refractory checks.
    private var lastAcceptedJumpTimestamp: TimeInterval?

    public init(profile: JumpDeviceProfile = .iPhonePocket) {
        self.profile = profile
        config = .profile(profile)
        debugState = JumpDetectorDebugState(
            profile: profile,
            dominantAxis: config.axis,
            chosenPolarity: config.polarity
        )
    }

    /// Processes one raw motion sample.
    /// The detector only inspects the configured raw acceleration axis and threshold for the profile.
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

    /// Reads the requested raw acceleration axis from a sample.
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

    /// Applies the fixed threshold rule for the active profile.
    private func thresholdSatisfied(value: Double) -> Bool {
        switch config.polarity {
        case .positivePeak, .positiveMagnitude:
            value > config.threshold
        case .negativeTrough:
            value < config.threshold
        }
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
