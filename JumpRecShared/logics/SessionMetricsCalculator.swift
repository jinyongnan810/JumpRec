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
    /// The minimum gap that counts as a short break.(extra 1 second for buffer)
    private static let smallBreakLowerBound: TimeInterval = 6
    /// The minimum gap that counts as a long break.(extra 1 second for buffer)
    private static let longBreakLowerBound: TimeInterval = 16
    /// Minimum spacing between two distinct rope turns; closer triggers are split-peak glitches.
    private static let doubleUnderLowerBound: TimeInterval = 0.16
    /// Unconditional maximum gap between two Watch rope turns that counts as a single double-under.
    private static let doubleUnderUpperBound: TimeInterval = 0.25
    /// Adaptive upper bound when a Watch turn pair is markedly faster than the current streak rhythm.
    private static let adaptiveDoubleUnderUpperBound: TimeInterval = 0.325
    /// Maximum fraction of recent single-under cadence allowed for adaptive double-under pairing.
    private static let relativeDoubleUnderPaceFactor: Double = 0.84
    /// Typical single-under turn interval range used to estimate the current streak cadence.
    private static let singleUnderCadenceRange: ClosedRange<TimeInterval> = 0.29 ... 0.50
    /// Pause duration that resets the local single-under cadence baseline.
    private static let doubleUnderStreakResetGap: TimeInterval = 0.80

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

    /// Counts non-overlapping Watch rope-turn pairs using rapid intervals and local cadence drops.
    public static func doubleUndersCount(from jumpOffsets: [TimeInterval]) -> Int {
        guard jumpOffsets.count > 1 else { return 0 }

        // Collapse sub-0.16s triggers caused by rope-snag split peaks on a single jump.
        var cleanedOffsets: [TimeInterval] = []
        cleanedOffsets.reserveCapacity(jumpOffsets.count)
        for offset in jumpOffsets {
            if let lastOffset = cleanedOffsets.last,
               offset - lastOffset > 0,
               offset - lastOffset < doubleUnderLowerBound
            {
                continue
            }
            cleanedOffsets.append(offset)
        }
        guard cleanedOffsets.count > 1 else { return 0 }

        var count = 0
        var index = 1
        var recentSingleIntervals: [TimeInterval] = []

        while index < cleanedOffsets.count {
            let interval = cleanedOffsets[index] - cleanedOffsets[index - 1]
            if interval <= 0 {
                index += 1
                continue
            }
            if interval > doubleUnderStreakResetGap {
                recentSingleIntervals.removeAll(keepingCapacity: true)
                index += 1
                continue
            }

            let isUnconditionalDoubleUnder =
                interval >= doubleUnderLowerBound && interval <= doubleUnderUpperBound
            let isRhythmRelativeDoubleUnder: Bool
            if recentSingleIntervals.count >= 2 {
                let recentCount = recentSingleIntervals.count
                let recentMean = (recentSingleIntervals[recentCount - 2] + recentSingleIntervals[recentCount - 1]) / 2.0
                isRhythmRelativeDoubleUnder =
                    interval >= doubleUnderLowerBound &&
                    interval <= adaptiveDoubleUnderUpperBound &&
                    interval <= recentMean * relativeDoubleUnderPaceFactor
            } else {
                isRhythmRelativeDoubleUnder = false
            }

            if isUnconditionalDoubleUnder || isRhythmRelativeDoubleUnder {
                count += 1
                if index + 1 < cleanedOffsets.count,
                   cleanedOffsets[index + 1] - cleanedOffsets[index] > doubleUnderStreakResetGap
                {
                    recentSingleIntervals.removeAll(keepingCapacity: true)
                }
                // Consume both turns so the second turn cannot pair with the following jump.
                index += 2
            } else {
                if singleUnderCadenceRange.contains(interval) {
                    recentSingleIntervals.append(interval)
                }
                index += 1
            }
        }

        return count
    }
}
