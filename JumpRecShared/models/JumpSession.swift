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

    /// Longest uninterrupted jump streak without a short or long break.
    public var longestStreak: Int = 0

    /// Average heart rate during the session in beats per minute.
    public var averageHeartRate: Int?

    /// Peak heart rate during the session in beats per minute.
    public var peakHeartRate: Int?

    /// Optional AI-generated recap for the session.
    public var aiComment: String?

    /// Normalized rate samples for charting and analytics.
    /// When this session is deleted, related samples are automatically deleted.
    @Relationship(deleteRule: .cascade, inverse: \SessionRateSample.session)
    public var rateSamples: [SessionRateSample]?

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
    ///   - longestStreak: Longest uninterrupted jump streak (defaults to 0)
    ///   - averageHeartRate: Average heart rate in bpm
    ///   - peakHeartRate: Peak heart rate in bpm
    public init(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        peakRate: Double,
        averageRate: Double? = nil,
        caloriesBurned: Double,
        smallBreaksCount: Int = 0,
        longBreaksCount: Int = 0,
        longestStreak: Int = 0,
        averageHeartRate: Int? = nil,
        peakHeartRate: Int? = nil,
        aiComment: String? = nil
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
        self.longestStreak = longestStreak
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        self.aiComment = aiComment
    }
}

public extension JumpSession {
    /// Returns the session duration formatted as `mm:ss`.
    var formattedDuration: String {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    /// Returns the formatted jump count text.
    var formattedJumpCount: String {
        jumpCount.formatted()
    }

    /// Returns the formatted calories text.
    var formattedCalories: String {
        "\(Int(caloriesBurned.rounded()))"
    }

    /// Returns the formatted average-rate text.
    func formattedAverageRate(placeholder: String = "--") -> String {
        guard let averageRate else { return placeholder }
        return localizedRateText(Int(averageRate.rounded()))
    }

    /// Returns the formatted peak-rate text.
    func formattedPeakRate(placeholder: String = "--") -> String {
        guard let peakRate else { return placeholder }
        return localizedRateText(Int(peakRate.rounded()))
    }

    /// Returns the formatted longest-streak text.
    var formattedLongestStreak: String {
        longestStreak.formatted()
    }

    /// Returns the formatted small-break count.
    var formattedSmallBreaksCount: String {
        smallBreaksCount.formatted()
    }

    /// Returns the formatted long-break count.
    var formattedLongBreaksCount: String {
        longBreaksCount.formatted()
    }

    /// Returns the formatted average heart-rate text.
    func formattedAverageHeartRate(placeholder: String = "--") -> String {
        formattedHeartRate(averageHeartRate, placeholder: placeholder)
    }

    /// Returns the formatted peak heart-rate text.
    func formattedPeakHeartRate(placeholder: String = "--") -> String {
        formattedHeartRate(peakHeartRate, placeholder: placeholder)
    }

    /// Formats an optional heart-rate value for display.
    private func formattedHeartRate(_ value: Int?, placeholder: String) -> String {
        guard let value else { return placeholder }
        return "\(value) bpm"
    }
}
