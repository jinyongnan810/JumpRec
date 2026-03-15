//
//  MotionSample.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/28.
//

import Foundation

/// A device-agnostic representation of a single motion data point.
/// Works with data from Apple Watch (CMMotionManager), iPhone (CMMotionManager),
/// and AirPods (CMHeadphoneMotionManager).
public struct MotionSample {
    // MARK: - Stored Properties

    /// User acceleration with gravity removed (in g's), per axis.
    public let userAccelerationX: Double
    public let userAccelerationY: Double
    public let userAccelerationZ: Double

    /// Rotation rate (in radians/second), per axis.
    public let rotationRateX: Double
    public let rotationRateY: Double
    public let rotationRateZ: Double

    /// Monotonic timestamp of the sample (seconds).
    /// On Apple Watch / iPhone this is `CMDeviceMotion.timestamp`.
    /// For AirPods you may use `ProcessInfo.processInfo.systemUptime` or similar.
    public let timestamp: TimeInterval

    // MARK: - Initialization

    /// Creates a normalized motion sample from raw motion sensor values.
    public init(
        userAccelerationX: Double,
        userAccelerationY: Double,
        userAccelerationZ: Double,
        rotationRateX: Double,
        rotationRateY: Double,
        rotationRateZ: Double,
        timestamp: TimeInterval
    ) {
        self.userAccelerationX = userAccelerationX
        self.userAccelerationY = userAccelerationY
        self.userAccelerationZ = userAccelerationZ
        self.rotationRateX = rotationRateX
        self.rotationRateY = rotationRateY
        self.rotationRateZ = rotationRateZ
        self.timestamp = timestamp
    }
}
