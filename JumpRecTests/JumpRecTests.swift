//
//  JumpRecTests.swift
//  JumpRecTests
//
//  Created by kinn on 2026/03/10.
//

import Foundation
@testable import JumpRec
import SwiftData
import Testing

struct JumpRecTests {
    @MainActor
    @Test func testLongestSessionRecordRequiresDurationGoal() throws {
        let store = try MyDataStore.makePreviewStore(qualifiedWorkoutCount: 0)
        let startedAt = Date(timeIntervalSince1970: 1_000_000)

        func makeSession(duration: TimeInterval) -> JumpSession {
            JumpSession(
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(duration),
                jumpCount: 300,
                peakRate: 150,
                caloriesBurned: 30
            )
        }

        let countSession = makeSession(duration: 600)
        let legacySession = makeSession(duration: 900)
        for session in [countSession, legacySession] {
            store.modelContext.insert(session)
            let updatedKinds = store.upsertPersonalRecords(for: session)
            #expect(!updatedKinds.contains(.longestSession))
        }

        store.backfillPersonalRecordsIfNeeded()
        let historicalRecords = try store.modelContext.fetch(FetchDescriptor<PersonalRecord>())
        #expect(!historicalRecords.contains { $0.kind == .longestSession })

        let thresholdSession = makeSession(duration: 60)
        #expect(!store.upsertPersonalRecords(for: thresholdSession, goalType: .time).contains(.longestSession))

        let durationSession = makeSession(duration: 120)
        store.modelContext.insert(durationSession)
        #expect(store.upsertPersonalRecords(for: durationSession, goalType: .time).contains(.longestSession))
        #expect(!store.upsertPersonalRecords(for: countSession, goalType: .count).contains(.longestSession))
        #expect(!store.upsertPersonalRecords(for: legacySession).contains(.longestSession))

        store.backfillPersonalRecordsIfNeeded()
        let records = try store.modelContext.fetch(FetchDescriptor<PersonalRecord>())
        #expect(records.first { $0.kind == .longestSession }?.metricValue == 120)
    }

    @MainActor
    @Test func testMostDoubleUndersRecordRequiresPositiveWatchCount() throws {
        let store = try MyDataStore.makePreviewStore(qualifiedWorkoutCount: 0)
        let startedAt = Date(timeIntervalSince1970: 1_000_000)

        func makeSession(doubleUndersCount: Int?, offsetSeconds: TimeInterval = 0) -> JumpSession {
            let start = startedAt.addingTimeInterval(offsetSeconds)
            return JumpSession(
                startedAt: start,
                endedAt: start.addingTimeInterval(180),
                jumpCount: 300,
                peakRate: 160,
                caloriesBurned: 35,
                doubleUndersCount: doubleUndersCount
            )
        }

        let unsupportedSession = makeSession(doubleUndersCount: nil)
        let zeroDoubleUndersSession = makeSession(doubleUndersCount: 0, offsetSeconds: 300)
        #expect(!store.upsertPersonalRecords(for: unsupportedSession).contains(.mostDoubleUnders))
        #expect(!store.upsertPersonalRecords(for: zeroDoubleUndersSession).contains(.mostDoubleUnders))

        let firstRecordSession = makeSession(doubleUndersCount: 12, offsetSeconds: 600)
        #expect(store.upsertPersonalRecords(for: firstRecordSession).contains(.mostDoubleUnders))

        let lowerCountSession = makeSession(doubleUndersCount: 8, offsetSeconds: 900)
        #expect(!store.upsertPersonalRecords(for: lowerCountSession).contains(.mostDoubleUnders))

        let higherCountSession = makeSession(doubleUndersCount: 25, offsetSeconds: 1200)
        #expect(store.upsertPersonalRecords(for: higherCountSession).contains(.mostDoubleUnders))

        let records = try store.modelContext.fetch(FetchDescriptor<PersonalRecord>())
        #expect(records.first { $0.kind == .mostDoubleUnders }?.metricValue == 25)
    }

    @Test func testMakeRateSamplesForSteady150Rate() async throws {
        let jumpOffsets = stride(from: 0.4, through: 60.0, by: 0.4).map(\.self)
        let samples = SessionMetricsCalculator.makeRateSamples(
            jumpOffsets: jumpOffsets,
            durationSeconds: 60
        )

        #expect(samples.count == 12)
        #expect(samples.map(\.secondOffset) == Array(stride(from: 5, through: 60, by: 5)))
        #expect(samples.map { "\($0.rate)" } == ["144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0"])
    }

    @Test func testRhythmConsistencyScoreRewardsSteadySessions() async throws {
        let steadySamples = [
            150.0, 150.0, 150.0, 150.0, 150.0, 150.0,
            150.0, 150.0, 150.0, 150.0, 150.0, 150.0,
        ].enumerated().map { index, rate in
            RateSamplePoint(secondOffset: (index + 1) * 5, rate: Float(rate))
        }

        let unevenSamples = [
            60.0, 240.0, 60.0, 240.0, 60.0, 240.0,
            60.0, 240.0, 60.0, 240.0, 60.0, 240.0,
        ].enumerated().map { index, rate in
            RateSamplePoint(secondOffset: (index + 1) * 5, rate: Float(rate))
        }

        let steadyScore = try #require(SessionMetricsCalculator.rhythmConsistencyScore(from: steadySamples))
        let unevenScore = try #require(SessionMetricsCalculator.rhythmConsistencyScore(from: unevenSamples))

        #expect(steadyScore == 1.0)
        #expect(unevenScore == 0.4)
    }

    @Test func testAverageRateUsesWholeSessionDuration() async throws {
        let averageRate = try #require(SessionMetricsCalculator.averageRate(jumpCount: 540, durationSeconds: 180))
        #expect(averageRate == 180.0)
    }

    @Test func testCaloriesPerMinuteUsesSessionDuration() async throws {
        let value = try #require(SessionMetricsCalculator.caloriesPerMinute(caloriesBurned: 90, durationSeconds: 300))
        #expect(value == 18.0)
    }

    @Test func testDoubleUndersCountPairsRapidTurnsWithoutOverlapping() async throws {
        let offsets: [TimeInterval] = [
            0.40,
            0.85,
            1.03, // Double under #1 (interval 0.18s)
            1.20, // Starts next jump even though 0.17s after 1.03, because 1.03 was consumed
            1.38, // Double under #2 (interval 0.18s)
            1.90,
            2.15, // Double under #3 (interval 0.25s boundary)
            2.41, // Single jump (interval 0.26s)
        ]

        #expect(SessionMetricsCalculator.doubleUndersCount(from: offsets) == 3)
        #expect(SessionMetricsCalculator.doubleUndersCount(from: [0.50]) == 0)
    }

    @Test func testDoubleUndersCountDetectsRhythmDropAndIgnoresSplitPeaksAndSteadyFastSingles() async throws {
        let offsets: [TimeInterval] = [
            0.40,
            0.78, // Single (0.38s)
            1.16, // Single (0.38s)
            1.54, // Single (0.38s)
            1.66, // Split-peak glitch (0.12s < 0.16s), collapsed into 1.54
            1.94, // Single (0.40s from 1.54)
            2.23, // Double under #1 (0.29s from 1.94)
            2.63, // Transition to next jump
            2.92, // Double under #2 (0.29s from 2.63)
            4.50, // Break > 0.80s resets cadence baseline
            4.81, // Steady fast single (0.31s)
            5.11, // Steady fast single (0.30s)
            5.41, // Steady fast single (0.30s)
            5.71, // Steady fast single (0.30s)
            6.01, // Steady fast single (0.30s)
        ]

        #expect(SessionMetricsCalculator.doubleUndersCount(from: offsets) == 2)
    }

    @Test func testWatchDetectorCountsWhipConfirmedDoubleUnders() async throws {
        let detector = JumpDetector(profile: .watch)
        let samples = [
            // Fast single-unders (0.30s apart, below whip thresholds)
            makeSample(z: 1.00, timestamp: 0.00),
            makeSample(z: 4.50, timestamp: 0.05),
            makeSample(z: -3.50, timestamp: 0.15),
            makeSample(z: 1.00, timestamp: 0.30),
            makeSample(z: 4.50, timestamp: 0.35),
            makeSample(z: -3.50, timestamp: 0.45),
            // Double-under pair (0.29s apart, strong wrist whip + >= 2.5g second turn)
            makeSample(z: 1.20, timestamp: 0.70),
            makeSample(z: 6.00, timestamp: 0.76),
            makeSample(z: -4.50, timestamp: 0.85),
            makeSample(z: 1.00, timestamp: 0.99),
            makeSample(z: 3.40, timestamp: 1.04),
            makeSample(z: -1.00, timestamp: 1.12),
        ]

        let jumps = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(jumps == 4)
        #expect(detector.doubleUndersCount == 1)

        detector.reset()
        #expect(detector.doubleUndersCount == 0)
    }

    @Test func testHeadphoneProfileCountsOnlyNegativeZBelowThresholdAfterRearm() async throws {
        let detector = JumpDetector(profile: .headphones)
        let samples = [
            makeSample(z: -1.10, timestamp: 0.00),
            makeSample(z: -1.25, timestamp: 0.15),
            makeSample(z: 0.05, timestamp: 0.25),
            makeSample(z: -1.30, timestamp: 0.35),
            makeSample(z: 0.10, timestamp: 0.45),
            makeSample(z: -1.35, timestamp: 0.55),
            makeSample(z: -0.80, timestamp: 0.70),
        ]

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count == 2)
    }

    @Test func testWatchProfileCountsOnlyPositiveZAboveThresholdAfterRearm() async throws {
        let detector = JumpDetector(profile: .watch)
        let samples = [
            makeSample(z: 0.79, timestamp: 0.00),
            makeSample(z: 0.81, timestamp: 0.15),
            makeSample(z: -0.05, timestamp: 0.25),
            makeSample(z: 0.95, timestamp: 0.35),
            makeSample(z: -0.10, timestamp: 0.45),
            makeSample(z: 1.00, timestamp: 0.55),
            makeSample(z: 0.40, timestamp: 0.70),
        ]

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count == 2)
    }

    @Test func testPositiveThresholdAdjustmentRaisesPositiveProfileThreshold() async throws {
        let detector = JumpDetector(profile: .watch, thresholdAdjustmentPercentage: 50)

        #expect(!detector.processMotionSample(makeSample(z: 1.19, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: 1.21, timestamp: 0.30)))
    }

    @Test func testPositiveThresholdAdjustmentMakesNegativeProfileMoreNegative() async throws {
        let detector = JumpDetector(profile: .headphones, thresholdAdjustmentPercentage: 50)

        #expect(!detector.processMotionSample(makeSample(z: -1.79, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: -1.81, timestamp: 0.30)))
    }

    @Test func testNegativeThresholdAdjustmentLowersPositiveProfileThreshold() async throws {
        let detector = JumpDetector(profile: .watch, thresholdAdjustmentPercentage: -50)

        #expect(!detector.processMotionSample(makeSample(z: 0.39, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: 0.41, timestamp: 0.30)))
    }

    @Test func testThresholdAdjustmentIsClampedToSupportedRange() async throws {
        let detector = JumpDetector(profile: .watch, thresholdAdjustmentPercentage: 100)

        #expect(!detector.processMotionSample(makeSample(z: 1.19, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: 1.21, timestamp: 0.30)))
    }

    @Test func testAllProfilesUse100MillisecondMinimumInterval() async throws {
        let headphoneDetector = JumpDetector(profile: .headphones)
        let watchDetector = JumpDetector(profile: .watch)

        let headphoneCount = [
            makeSample(z: -1.30, timestamp: 0.00),
            makeSample(z: 0.20, timestamp: 0.04),
            makeSample(z: -1.40, timestamp: 0.08),
            makeSample(z: -1.50, timestamp: 0.11),
        ].reduce(into: 0) { partialResult, sample in
            if headphoneDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        let watchCount = [
            makeSample(z: 0.90, timestamp: 0.00),
            makeSample(z: -0.20, timestamp: 0.04),
            makeSample(z: 1.00, timestamp: 0.08),
            makeSample(z: 1.10, timestamp: 0.11),
        ].reduce(into: 0) { partialResult, sample in
            if watchDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(headphoneCount == 2)
        #expect(watchCount == 2)
    }

    @Test func testResetClearsRefractoryAndRearmState() async throws {
        let detector = JumpDetector(profile: .watch)

        #expect(detector.processMotionSample(makeSample(z: 0.90, timestamp: 0.00)))
        #expect(!detector.processMotionSample(makeSample(z: 0.95, timestamp: 0.05)))

        detector.reset()

        #expect(detector.processMotionSample(makeSample(z: 0.95, timestamp: 0.05)))
    }

    @Test func testRecordedWatchMotionCSVsDetectExpectedJumpsAndDoubleUnders() async throws {
        let normalResult = try replayMotionCSV(named: "watch-normal.csv", profile: .watch)
        #expect(normalResult.jumpOffsets.count == 200)
        #expect(normalResult.detector.doubleUndersCount == 0)
        #expect(SessionMetricsCalculator.doubleUndersCount(from: normalResult.jumpOffsets) == 0)

        let sevenDoubleUndersResult = try replayMotionCSV(named: "watch-7-doubleunders.csv", profile: .watch)
        #expect(sevenDoubleUndersResult.jumpOffsets.count == 200)
        #expect(sevenDoubleUndersResult.detector.doubleUndersCount == 7)
        #expect(SessionMetricsCalculator.doubleUndersCount(from: sevenDoubleUndersResult.jumpOffsets) == 7)

        let seventeenDoubleUndersResult = try replayMotionCSV(named: "watch-17-doubleunders.csv", profile: .watch)
        #expect(seventeenDoubleUndersResult.jumpOffsets.count == 200)
        #expect(seventeenDoubleUndersResult.detector.doubleUndersCount == 17)
        #expect(SessionMetricsCalculator.doubleUndersCount(from: seventeenDoubleUndersResult.jumpOffsets) == 16)
    }

    @Test func testRecordedHeadphoneMotionCSVsDetectExpectedJumps() async throws {
        let normalResult = try replayMotionCSV(named: "headphone-normal.csv", profile: .headphones)
        #expect(normalResult.jumpOffsets.count == 200)

        let fiveDoubleUndersResult = try replayMotionCSV(named: "headphone-5-doubleunders.csv", profile: .headphones)
        #expect(fiveDoubleUndersResult.jumpOffsets.count == 200)
    }
}

private extension JumpRecTests {
    /// Produces a raw `MotionSample` with only the requested axes populated.
    func makeSample(
        x: Double = 0,
        y: Double = 0,
        z: Double = 0,
        timestamp: TimeInterval
    ) -> MotionSample {
        MotionSample(
            userAccelerationX: x,
            userAccelerationY: y,
            userAccelerationZ: z,
            rotationRateX: 0,
            rotationRateY: 0,
            rotationRateZ: 0,
            timestamp: timestamp
        )
    }

    /// Loads recorded sensor rows from `Analysis/motion-data/<filename>`.
    func loadMotionSamples(named filename: String) throws -> [MotionSample] {
        let fileURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Analysis")
            .appendingPathComponent("motion-data")
            .appendingPathComponent(filename)
        let contents = try String(contentsOf: fileURL, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline)
        guard lines.count > 1 else {
            return []
        }

        var samples: [MotionSample] = []
        samples.reserveCapacity(lines.count - 1)
        for line in lines.dropFirst() {
            let columns = line.split(separator: ",")
            guard columns.count == 7,
                  let timestamp = Double(columns[0]),
                  let ax = Double(columns[1]),
                  let ay = Double(columns[2]),
                  let az = Double(columns[3]),
                  let rx = Double(columns[4]),
                  let ry = Double(columns[5]),
                  let rz = Double(columns[6])
            else {
                continue
            }
            samples.append(
                MotionSample(
                    userAccelerationX: ax,
                    userAccelerationY: ay,
                    userAccelerationZ: az,
                    rotationRateX: rx,
                    rotationRateY: ry,
                    rotationRateZ: rz,
                    timestamp: timestamp
                )
            )
        }
        return samples
    }

    /// Replays a recorded motion CSV through a fresh detector and returns accepted jump offsets.
    func replayMotionCSV(
        named filename: String,
        profile: JumpDeviceProfile
    ) throws -> (detector: JumpDetector, jumpOffsets: [TimeInterval]) {
        let samples = try loadMotionSamples(named: filename)
        try #require(!samples.isEmpty)

        let detector = JumpDetector(profile: profile)
        var jumpOffsets: [TimeInterval] = []
        for sample in samples where detector.processMotionSample(sample) {
            jumpOffsets.append(sample.timestamp)
        }
        return (detector, jumpOffsets)
    }
}
