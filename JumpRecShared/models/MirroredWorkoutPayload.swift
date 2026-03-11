//
//  MirroredWorkoutPayload.swift
//  JumpRecShared
//

import Foundation

public struct MirroredWorkoutPayload: Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case started
        case jump
        case metrics
        case ended
    }

    public let kind: Kind
    public let startTime: Date?
    public let endTime: Date?
    public let goalType: GoalType?
    public let goalValue: Int?
    public let jumpCount: Int?
    public let jumpOffset: TimeInterval?
    public let energyBurned: Double?
    public let averageHeartRate: Int?
    public let peakHeartRate: Int?

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
