//
//  JumpRecTests.swift
//  JumpRecTests
//
//  Created by Yuunan kin on 2026/03/10.
//

import Foundation
import Testing

struct JumpRecTests {
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
