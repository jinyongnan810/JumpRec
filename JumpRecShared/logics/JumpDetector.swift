//
//  JumpDetector.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/28.
//

import Foundation

/// Detects jumps from device-agnostic `MotionSample` data.
/// Can be used with Apple Watch, iPhone, or AirPods motion sources.
public final class JumpDetector {
    // MARK: - Configuration

    /// Minimum time (seconds) that must elapse between two consecutive detected jumps.
    public var minTimeBetweenJumps: TimeInterval = 0.30

    /// Vertical acceleration threshold (in g's) that must be exceeded to count as a jump.
    public var accelerationThreshold: Double = 0.8

    // MARK: - State

    private var lastJumpTimestamp: TimeInterval = 0

    // MARK: - Initialization

    public init(
        minTimeBetweenJumps: TimeInterval = 0.30,
        accelerationThreshold: Double = 0.8
    ) {
        self.minTimeBetweenJumps = minTimeBetweenJumps
        self.accelerationThreshold = accelerationThreshold
    }

    // MARK: - Public API

    /// Process a single motion sample and determine if it represents a jump.
    /// - Parameter sample: A device-agnostic motion data point.
    /// - Returns: `true` if a jump was detected.
    public func processMotionSample(_ sample: MotionSample) -> Bool {
        // 1. Enforce minimum time between jumps
        guard sample.timestamp - lastJumpTimestamp > minTimeBetweenJumps else {
            return false
        }

        // 2. Check if vertical acceleration exceeds threshold
        let isJump = sample.userAccelerationY > accelerationThreshold

        if isJump {
            lastJumpTimestamp = sample.timestamp
        }

        return isJump
    }

    /// Reset internal state. Call when starting a new session.
    public func reset() {
        lastJumpTimestamp = 0
    }
}
