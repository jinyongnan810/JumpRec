//
//  MirroredWorkoutPayload.swift
//  JumpRecShared
//

import Foundation

/// Transfers mirrored workout events and metrics between Apple Watch and iPhone.
public struct MirroredWorkoutPayload: Codable, Sendable {
    /// Describes the kind of mirrored event contained in the payload.
    public enum Kind: String, Codable, Sendable {
        /// Indicates that the mirrored workout has started.
        case started
        /// Indicates that a jump event occurred.
        case jump
        /// Indicates that metrics like heart rate or calories changed.
        case metrics
        /// Indicates that the mirrored workout ended.
        case ended
    }

    // MARK: - Stored Properties

    /// The type of mirrored workout event.
    public let kind: Kind
    /// The mirrored workout start time, when applicable.
    public let startTime: Date?
    /// The mirrored workout end time, when applicable.
    public let endTime: Date?
    /// The configured goal type for the session.
    public let goalType: GoalType?
    /// The configured goal value for the session.
    public let goalValue: Int?
    /// The current jump count, when included.
    public let jumpCount: Int?
    /// The jump offset relative to the session start, when included.
    public let jumpOffset: TimeInterval?
    /// The latest active energy burned value.
    public let energyBurned: Double?
    /// The latest average heart rate value.
    public let averageHeartRate: Int?
    /// The latest peak heart rate value.
    public let peakHeartRate: Int?

    // MARK: - Initialization

    /// Creates a mirrored workout payload for the provided event data.
    public init(
        kind: Kind,
        startTime: Date? = nil,
        endTime: Date? = nil,
        goalType: GoalType? = nil,
        goalValue: Int? = nil,
        jumpCount: Int? = nil,
        jumpOffset: TimeInterval? = nil,
        energyBurned: Double? = nil,
        averageHeartRate: Int? = nil,
        peakHeartRate: Int? = nil
    ) {
        self.kind = kind
        self.startTime = startTime
        self.endTime = endTime
        self.goalType = goalType
        self.goalValue = goalValue
        self.jumpCount = jumpCount
        self.jumpOffset = jumpOffset
        self.energyBurned = energyBurned
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
    }
}
