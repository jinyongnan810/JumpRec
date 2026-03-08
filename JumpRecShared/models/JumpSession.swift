//
//  JumpSession.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/12/27.
//

import Foundation
import SwiftData

/// Represents a single jump rope session with summary statistics.
/// This model stores the high-level metadata and calculated metrics for a workout session.
/// Detailed time-series data is stored in related `SessionRateSample` rows.
@Model
public final class JumpSession {
    /// Unique identifier for the session
    public var id: UUID = UUID()

    /// Timestamp when the jump rope session started
    public var startedAt: Date = Date()

    /// Timestamp when the jump rope session ended
    public var endedAt: Date = Date()

    /// Total number of jumps completed during the session
    public var jumpCount: Int = 0

    /// Peak jump rate (jumps per minute) achieved during the session
    public var peakRate: Double?

    /// Average jump rate (jumps per minute) across the session
    public var averageRate: Double?

    /// Estimated calories burned during the session
    public var caloriesBurned: Double = 0

    /// Session duration in seconds
    public var durationSeconds: Int = 0

    /// Number of small breaks taken during the session
    public var smallBreaksCount: Int = 0

    /// Number of long breaks taken during the session
    public var longBreaksCount: Int = 0

    /// Normalized rate samples for charting and analytics.
    /// When this session is deleted, related samples are automatically deleted.
    @Relationship(deleteRule: .cascade, inverse: \SessionRateSample.session)
    public var rateSamples: [SessionRateSample] = []

    /// Initializes a new jump rope session with summary statistics
    /// - Parameters:
    ///   - startedAt: Session start time
    ///   - endedAt: Session end time
    ///   - jumpCount: Total jumps completed
    ///   - peakRate: Highest jump rate achieved (jumps per minute)
    ///   - averageRate: Average jump rate achieved (jumps per minute)
    ///   - caloriesBurned: Estimated calories burned
    ///   - smallBreaksCount: Number of small breaks (defaults to 0)
    ///   - longBreaksCount: Number of long breaks (defaults to 0)
    public init(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        peakRate: Double,
        averageRate: Double? = nil,
        caloriesBurned: Double,
        smallBreaksCount: Int = 0,
        longBreaksCount: Int = 0
    ) {
        id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.jumpCount = jumpCount
        self.peakRate = peakRate
        self.averageRate = averageRate
        self.caloriesBurned = caloriesBurned
        durationSeconds = max(0, Int(endedAt.timeIntervalSince(startedAt)))
        self.smallBreaksCount = smallBreaksCount
        self.longBreaksCount = longBreaksCount
    }
}
