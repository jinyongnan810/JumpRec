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
        let startedAt = Date()
        let endedAt = startedAt.addingTimeInterval(60)
        let jumpOffsets = stride(from: 0.4, through: 60.0, by: 0.4).map(\.self)
        let session = JumpSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpOffsets.count,
            peakRate: 0,
            caloriesBurned: 0
        )

        let samples = SessionMetricsCalculator.makeRateSamples(
            for: session,
            jumpOffsets: jumpOffsets,
            durationSeconds: 60
        )

        #expect(samples.count == 12)
        #expect(samples.map(\.secondOffset) == Array(stride(from: 5, through: 60, by: 5)))
        #expect(samples.map { "\($0.rate)" } == ["144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0", "144.0", "156.0"])
    }

    @Test func testIPhoneProfileCountsOnlyPositiveYAboveThreshold() async throws {
        let detector = JumpDetector(profile: .iPhonePocket)
        let samples = [
            makeSample(y: 1.19, timestamp: 0.00),
            makeSample(y: 1.21, timestamp: 0.30),
            makeSample(y: 1.30, timestamp: 0.60),
            makeSample(y: 0.90, timestamp: 0.90),
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

    @Test func testAllProfilesUse250MillisecondMinimumInterval() async throws {
        let iPhoneDetector = JumpDetector(profile: .iPhonePocket)
        let headphoneDetector = JumpDetector(profile: .headphones)
        let watchDetector = JumpDetector(profile: .watch)

        let iPhoneCount = [
            makeSample(y: 1.30, timestamp: 0.00),
            makeSample(y: 1.35, timestamp: 0.10),
            makeSample(y: 1.40, timestamp: 0.26),
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
