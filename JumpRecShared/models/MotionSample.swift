//
//  MotionSample.swift
//  JumpRec
//
//  Created by kinn on 2026/02/28.
//

import Foundation

/// Motion sample shared by Watch, iPhone, and headphone detectors.
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

    /// Monotonic sample timestamp in seconds.
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
