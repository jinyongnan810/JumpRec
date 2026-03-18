//
//  SessionMetricsCalculator.swift
//  JumpRec
//
//  Created by Codex on 2026/03/09.
//

import Foundation

/// Shared calculation helpers for session summary metrics and rate samples.
public enum SessionMetricsCalculator {
    // MARK: - Constants

    /// The spacing between generated chart samples in seconds.
    private static let bucketSeconds = 5
    /// The rolling window used to compute jump-rate samples.
    private static let rollingWindowSeconds = 5
    /// The minimum gap that counts as a short break.
    private static let smallBreakLowerBound: TimeInterval = 5
    /// The minimum gap that counts as a long break.
    private static let longBreakLowerBound: TimeInterval = 15

    // MARK: - Rate Metrics

    /// Generates normalized rate samples for charting a completed session.
    public static func makeRateSamples(
        for session: JumpSession,
        jumpOffsets: [TimeInterval],
        durationSeconds: Int
    ) -> [SessionRateSample] {
        guard durationSeconds > 0 else { return [] }

        guard !jumpOffsets.isEmpty else { return [] }

        var samples: [SessionRateSample] = []
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
            samples.append(SessionRateSample(session: session, secondOffset: second, rate: rate))
        }

        return samples
    }

    /// Returns the average jump rate for a session when duration is valid.
    public static func averageRate(jumpCount: Int, durationSeconds: Int) -> Double? {
        guard durationSeconds > 0 else { return nil }
        return Double(jumpCount) * 60.0 / Double(durationSeconds)
    }

    /// Returns the highest jump rate found in a sample series.
    public static func peakRate(from rateSamples: [SessionRateSample]) -> Double? {
        rateSamples.map(\.rate).max()
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
}
