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
    @Test func testLifetimeMilestoneThresholds() {
        #expect(LifetimeJumpMilestone.crossedThresholds(previousTotal: 999, newTotal: 1000) == [1000])
        #expect(LifetimeJumpMilestone.crossedThresholds(previousTotal: 1000, newTotal: 4999).isEmpty)
        #expect(LifetimeJumpMilestone.crossedThresholds(previousTotal: 900, newTotal: 26000) == [1000, 5000, 10000, 25000])
        #expect(LifetimeJumpMilestone.crossedThresholds(previousTotal: 99999, newTotal: 300_000) == [100_000, 200_000, 300_000])
        #expect(LifetimeJumpMilestone.crossedThresholds(previousTotal: 5000, newTotal: 5000).isEmpty)
    }

    @MainActor
    @Test func testLifetimeMilestonesUseHistoryWithoutRetroactiveAwards() throws {
        let store = try MyDataStore.makePreviewStore(qualifiedWorkoutCount: 0)
        let startedAt = Date(timeIntervalSince1970: 1_000_000)

        func makeSession(jumps: Int) -> JumpSession {
            JumpSession(
                startedAt: startedAt,
                endedAt: startedAt.addingTimeInterval(120),
                jumpCount: jumps,
                peakRate: 150,
                caloriesBurned: 30
            )
        }

        // Existing history contributes to totals without awarding already-passed thresholds.
        store.modelContext.insert(makeSession(jumps: 4900))
        let belowThreshold = makeSession(jumps: 50)
        store.addSession(session: belowThreshold, goalType: .count)
        #expect(belowThreshold.newlyAchievedJumpMilestone == nil)
        #expect(try store.modelContext.fetchCount(FetchDescriptor<LifetimeJumpMilestone>()) == 0)

        let crossingSession = makeSession(jumps: 25100)
        store.addSession(session: crossingSession, goalType: .time)
        #expect(crossingSession.newlyAchievedJumpMilestone == 25000)
        let earned = try store.modelContext.fetch(FetchDescriptor<LifetimeJumpMilestone>())
        #expect(Set(earned.map(\.jumpCount)) == [5000, 10000, 25000])

        // Deleting workouts keeps earned highlights and prevents awarding them a second time.
        for session in try store.modelContext.fetch(FetchDescriptor<JumpSession>()) {
            store.modelContext.delete(session)
        }
        try store.modelContext.save()
        store.modelContext.insert(makeSession(jumps: 4900))
        let repeatedCrossing = makeSession(jumps: 200)
        store.addSession(session: repeatedCrossing)
        #expect(repeatedCrossing.newlyAchievedJumpMilestone == nil)
        #expect(try store.modelContext.fetchCount(FetchDescriptor<LifetimeJumpMilestone>()) == 3)
    }

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

    @Test func testIPhoneProfileCountsMagnitudeAboveThresholdInAnyDirection() async throws {
        let detector = JumpDetector(profile: .iPhonePocket)
        let samples = [
            makeSample(x: 1.19, timestamp: 0.00),
            makeSample(x: 1.21, timestamp: 0.30),
            makeSample(y: 1.30, timestamp: 0.60),
            makeSample(z: -1.35, timestamp: 0.90),
            makeSample(x: 0.40, y: 0.50, z: 0.60, timestamp: 1.20),
        ]

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count == 3)
        #expect(detector.debugState.dominantAxis == .magnitude)
        #expect(detector.debugState.chosenPolarity == .positiveMagnitude)
    }

    @Test func testHeadphoneProfileCountsOnlyNegativeZBelowThreshold() async throws {
        let detector = JumpDetector(profile: .headphones)
        let samples = [
            makeSample(z: -1.10, timestamp: 0.00),
            makeSample(z: -1.25, timestamp: 0.30),
            makeSample(z: -1.35, timestamp: 0.61),
            makeSample(z: -0.80, timestamp: 0.95),
        ]

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count == 2)
        #expect(detector.debugState.dominantAxis == .z)
        #expect(detector.debugState.chosenPolarity == .negativeTrough)
    }

    @Test func testWatchProfileCountsOnlyPositiveYAboveThreshold() async throws {
        let detector = JumpDetector(profile: .watch)
        let samples = [
            makeSample(y: 0.79, timestamp: 0.00),
            makeSample(y: 0.81, timestamp: 0.30),
            makeSample(y: 1.00, timestamp: 0.62),
            makeSample(y: 0.40, timestamp: 1.00),
        ]

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count == 2)
        #expect(detector.debugState.dominantAxis == .y)
        #expect(detector.debugState.chosenPolarity == .positivePeak)
    }

    @Test func testPositiveThresholdAdjustmentRaisesPositiveProfileThreshold() async throws {
        let detector = JumpDetector(profile: .iPhonePocket, thresholdAdjustmentPercentage: 50)

        #expect(!detector.processMotionSample(makeSample(x: 1.79, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: -1.81, timestamp: 0.30)))
    }

    @Test func testPositiveThresholdAdjustmentMakesNegativeProfileMoreNegative() async throws {
        let detector = JumpDetector(profile: .headphones, thresholdAdjustmentPercentage: 50)

        #expect(!detector.processMotionSample(makeSample(z: -1.79, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: -1.81, timestamp: 0.30)))
    }

    @Test func testNegativeThresholdAdjustmentLowersPositiveProfileThreshold() async throws {
        let detector = JumpDetector(profile: .watch, thresholdAdjustmentPercentage: -50)

        #expect(!detector.processMotionSample(makeSample(y: 0.39, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(y: 0.41, timestamp: 0.30)))
    }

    @Test func testThresholdAdjustmentIsClampedToSupportedRange() async throws {
        let detector = JumpDetector(profile: .iPhonePocket, thresholdAdjustmentPercentage: 100)

        #expect(!detector.processMotionSample(makeSample(x: 1.79, timestamp: 0.00)))
        #expect(detector.processMotionSample(makeSample(z: -1.81, timestamp: 0.30)))
    }

    @Test func testAllProfilesUse250MillisecondMinimumInterval() async throws {
        let iPhoneDetector = JumpDetector(profile: .iPhonePocket)
        let headphoneDetector = JumpDetector(profile: .headphones)
        let watchDetector = JumpDetector(profile: .watch)

        let iPhoneCount = [
            makeSample(x: 1.30, timestamp: 0.00),
            makeSample(y: 1.35, timestamp: 0.10),
            makeSample(z: -1.40, timestamp: 0.26),
        ].reduce(into: 0) { partialResult, sample in
            if iPhoneDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        let headphoneCount = [
            makeSample(z: -1.30, timestamp: 0.00),
            makeSample(z: -1.40, timestamp: 0.12),
            makeSample(z: -1.50, timestamp: 0.28),
        ].reduce(into: 0) { partialResult, sample in
            if headphoneDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        let watchCount = [
            makeSample(y: 0.90, timestamp: 0.00),
            makeSample(y: 1.00, timestamp: 0.20),
            makeSample(y: 1.10, timestamp: 0.30),
        ].reduce(into: 0) { partialResult, sample in
            if watchDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(iPhoneCount == 2)
        #expect(headphoneCount == 2)
        #expect(watchCount == 2)
    }

    @Test func testResetClearsRefractoryState() async throws {
        let detector = JumpDetector(profile: .watch)

        #expect(detector.processMotionSample(makeSample(y: 0.90, timestamp: 0.00)))
        #expect(!detector.processMotionSample(makeSample(y: 0.95, timestamp: 0.10)))

        detector.reset()

        #expect(detector.processMotionSample(makeSample(y: 0.95, timestamp: 0.10)))
        #expect(detector.debugState.lastAcceptedJumpTimestamp == 0.10)
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
}
