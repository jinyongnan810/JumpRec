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
/// Detailed timing data for individual jumps is stored in the related `JumpSessionDetails` model.
@Model
public final class JumpSession {
    /// Unique identifier for the session
    public var id: UUID = UUID()

    /// Timestamp when the jump rope session started
    public var startedAt: Date

    /// Timestamp when the jump rope session ended
    public var endedAt: Date

    /// Total number of jumps completed during the session
    public var jumpCount: Int

    /// Peak jump rate (jumps per minute) achieved during the session
    public var peakRate: Double?

    /// Estimated calories burned during the session
    public var caloriesBurned: Double

    /// Number of small breaks taken during the session
    public var smallBreaksCount: Int

    /// Number of long breaks taken during the session
    public var longBreaksCount: Int

    /// Relationship to detailed session data (individual jump timestamps and rate points)
    /// When this session is deleted, the related details are automatically deleted (cascade)
    @Relationship(deleteRule: .cascade, inverse: \JumpSessionDetails.session)
    public var details: JumpSessionDetails?

    /// Initializes a new jump rope session with summary statistics
    /// - Parameters:
    ///   - startedAt: Session start time
    ///   - endedAt: Session end time
    ///   - jumpCount: Total jumps completed
    ///   - peakRate: Highest jump rate achieved (jumps per minute)
    ///   - caloriesBurned: Estimated calories burned
    ///   - smallBreaksCount: Number of small breaks (defaults to 0)
    ///   - longBreaksCount: Number of long breaks (defaults to 0)
    public init(startedAt: Date, endedAt: Date, jumpCount: Int, peakRate: Double, caloriesBurned: Double, smallBreaksCount: Int = 0, longBreaksCount: Int = 0) {
        id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.jumpCount = jumpCount
        self.peakRate = peakRate
        self.caloriesBurned = caloriesBurned
        self.smallBreaksCount = smallBreaksCount
        self.longBreaksCount = longBreaksCount
    }
}
