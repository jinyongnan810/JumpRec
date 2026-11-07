//
//  SessionMetricsCalculator.swift
//  JumpRec
//
//  Created by kinn on 2026/03/09.
//

import Foundation

/// Shared calculation helpers for session summary metrics and rate samples.
public nonisolated enum SessionMetricsCalculator {
    // MARK: - Constants

    /// The spacing between generated chart samples in seconds.
    private static let bucketSeconds = 5
    /// The rolling window used to compute jump-rate samples.
    private static let rollingWindowSeconds = 5
    /// The minimum gap that counts as a short break.
    private static let smallBreakLowerBound: TimeInterval = 5
    /// The minimum gap that counts as a long break.
    private static let longBreakLowerBound: TimeInterval = 15
    /// The maximum gap between two Watch rope turns that counts as a single double-under.
    private static let doubleJumpUpperBound: TimeInterval = 0.25

    // MARK: - Rate Metrics

    /// Generates normalized rate samples for charting a completed session.
    public static func makeRateSamples(
        jumpOffsets: [TimeInterval],
        durationSeconds: Int
    ) -> [RateSamplePoint] {
        guard durationSeconds > 0 else { return [] }

        guard !jumpOffsets.isEmpty else { return [] }

        var samples: [RateSamplePoint] = []
        var left = 0
        var right = 0
        var sampleSeconds = Array(stride(from: bucketSeconds, through: durationSeconds, by: bucketSeconds))

        if sampleSeconds.isEmpty || sampleSeconds.last != durationSeconds {
            sampleSeconds.append(durationSeconds)
        }

        for second in sampleSeconds {
            let upperBound = Double(second)
            let lowerBound = Double(max(0, second - rollingWindowSeconds))

            while left < jumpOffsets.count, jumpOffsets[left] <= lowerBound {
                left += 1
            }
            while right < jumpOffsets.count, jumpOffsets[right] <= upperBound {
                right += 1
            }

            let countInWindow = max(0, right - left)
            let effectiveWindowSeconds = min(rollingWindowSeconds, max(1, second))
            let rate = Double(countInWindow) * 60.0 / Double(effectiveWindowSeconds)
            samples.append(RateSamplePoint(secondOffset: second, rate: Float(rate)))
        }

        return samples
    }

    /// Returns the average jump rate for a session when duration is valid.
    public static func averageRate(jumpCount: Int, durationSeconds: Int) -> Double? {
        guard durationSeconds > 0 else { return nil }
        return Double(jumpCount) * 60.0 / Double(durationSeconds)
    }

    /// Returns the highest jump rate found in a sample series.
    public static func peakRate(from rateSamples: [RateSamplePoint]) -> Double? {
        rateSamples.map { Double($0.rate) }.max()
    }

    /// Scores pace consistency from 0 to 1; higher is steadier. Samples must be in time order.
    public static func rhythmConsistencyScore(from rateSamples: [RateSamplePoint]) -> Double? {
        guard rateSamples.count > 1 else { return nil }

        let rates = rateSamples.map { Double($0.rate) }
        let meanRate = rates.reduce(0, +) / Double(rates.count)
        guard meanRate > 0 else { return nil }

        let averageAbsoluteDeviation = rates
            .map { abs($0 - meanRate) }
            .reduce(0, +) / Double(rates.count)
        let normalizedDeviation = min(1, averageAbsoluteDeviation / meanRate)
        return max(0, 1 - normalizedDeviation)
    }

    /// Returns calories burned per minute for sessions with a valid duration.
    public static func caloriesPerMinute(caloriesBurned: Double, durationSeconds: Int) -> Double? {
        guard caloriesBurned > 0, durationSeconds > 0 else { return nil }
        return caloriesBurned / (Double(durationSeconds) / 60.0)
    }

    // MARK: - Break Metrics

    /// Derives short-break, long-break, and longest-streak metrics from jump offsets.
    public static func breakMetrics(from jumpOffsets: [TimeInterval]) -> (small: Int, long: Int, longestStreak: Int) {
        guard !jumpOffsets.isEmpty else { return (0, 0, 0) }
        guard jumpOffsets.count > 1 else { return (0, 0, 1) }

        var smallBreaksCount = 0
        var longBreaksCount = 0
        var longestStreak = 1
        var currentStreak = 1

        for index in 1 ..< jumpOffsets.count {
            let breakDuration = jumpOffsets[index] - jumpOffsets[index - 1]

            if breakDuration > longBreakLowerBound {
                longBreaksCount += 1
                longestStreak = max(longestStreak, currentStreak)
                currentStreak = 1
            } else if breakDuration > smallBreakLowerBound {
                smallBreaksCount += 1
                longestStreak = max(longestStreak, currentStreak)
                currentStreak = 1
            } else {
                currentStreak += 1
            }
        }

        return (smallBreaksCount, longBreaksCount, max(longestStreak, currentStreak))
    }

    /// Counts non-overlapping Watch rope-turn pairs separated by at most 0.25 seconds.
    public static func doubleJumpsCount(from jumpOffsets: [TimeInterval]) -> Int {
        guard jumpOffsets.count > 1 else { return 0 }

        var count = 0
        var index = 1
        while index < jumpOffsets.count {
            let interval = jumpOffsets[index] - jumpOffsets[index - 1]
            if interval > 0, interval <= doubleJumpUpperBound {
                count += 1
                // Consume both turns so the second turn cannot pair with the following jump.
                index += 2
            } else {
                index += 1
            }
        }

        return count
    }
}
