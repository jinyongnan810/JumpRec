//
//  JumpRecTests.swift
//  JumpRecTests
//
//  Created by Yuunan kin on 2026/03/10.
//

import Foundation
import JumpRecShared
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
        #expect(samples.map { "\($0.rate)" } == ["144.0", "150.0", "148.0", "150.0", "148.8", "150.0", "150.0", "150.0", "150.0", "150.0", "150.0", "150.0"])
    }

    @Test func testPocketProfileCountsDominantAxisPeriodically() async throws {
        let detector = JumpDetector(profile: .iPhonePocket)
        let samples = makePeriodicSamples(
            duration: 6.0,
            sampleRate: 40,
            dominantAxis: \.z,
            interval: 0.42,
            amplitude: 1.15
        )

        let count = samples.reduce(into: 0) { partialResult, sample in
            if detector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(count >= 8)
        #expect(detector.debugState.dominantAxis == .z)
        #expect(detector.debugState.chosenPolarity != nil)
    }

    @Test func testHeadphoneProfileIgnoresIsolatedSpikesUntilRhythmLocks() async throws {
        let detector = JumpDetector(profile: .headphones)
        var samples = makeIdleSamples(duration: 1.0, sampleRate: 50)
        samples += makeSpikeSamples(times: [1.15, 1.9], sampleRate: 50, axis: \.x, amplitude: 1.4)
        samples += makePeriodicSamples(
            duration: 4.0,
            sampleRate: 50,
            dominantAxis: \.x,
            interval: 0.45,
            amplitude: 1.1,
            startTime: 2.0
        )

        let timestamps = samples.compactMap { sample -> TimeInterval? in
            detector.processMotionSample(sample) ? sample.timestamp : nil
        }

        #expect(timestamps.count >= 4)
        #expect(timestamps.first ?? 0 > 3.5)
        #expect(detector.debugState.rhythmLocked)
    }

    @Test func testWatchProfileRequiresGyroAndAccelerationConfirmation() async throws {
        let confirmedDetector = JumpDetector(profile: .watch)
        let confirmedSamples = makeWatchSamples(duration: 5.0, sampleRate: 40, includeAccelerationConfirmation: true)
        let confirmedCount = confirmedSamples.reduce(into: 0) { partialResult, sample in
            if confirmedDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        let gyroOnlyDetector = JumpDetector(profile: .watch)
        let gyroOnlySamples = makeWatchSamples(duration: 5.0, sampleRate: 40, includeAccelerationConfirmation: false)
        let gyroOnlyCount = gyroOnlySamples.reduce(into: 0) { partialResult, sample in
            if gyroOnlyDetector.processMotionSample(sample) {
                partialResult += 1
            }
        }

        #expect(confirmedCount >= 6)
        #expect(gyroOnlyCount == 0)
    }
}

private extension JumpRecTests {
    typealias AxisKeyPath = WritableKeyPath<AxisComponents, Double>

    struct AxisComponents {
        var x: Double = 0
        var y: Double = 0
        var z: Double = 0
    }

    func makeIdleSamples(duration: TimeInterval, sampleRate: Double) -> [MotionSample] {
        makePeriodicSamples(
            duration: duration,
            sampleRate: sampleRate,
            dominantAxis: \.y,
            interval: 10,
            amplitude: 0,
            startTime: 0
        )
    }

    func makeSpikeSamples(
        times: [TimeInterval],
        sampleRate: Double,
        axis: AxisKeyPath,
        amplitude: Double
    ) -> [MotionSample] {
        times.map { time in
            var accel = AxisComponents()
            accel[keyPath: axis] = amplitude
            return MotionSample(
                userAccelerationX: accel.x,
                userAccelerationY: accel.y,
                userAccelerationZ: accel.z,
                rotationRateX: 0,
                rotationRateY: 0,
                rotationRateZ: 0,
                timestamp: time
            )
        }.sorted { $0.timestamp < $1.timestamp }
    }

    func makePeriodicSamples(
        duration: TimeInterval,
        sampleRate: Double,
        dominantAxis: AxisKeyPath,
        interval: TimeInterval,
        amplitude: Double,
        startTime: TimeInterval = 0
    ) -> [MotionSample] {
        let dt = 1 / sampleRate
        let endTime = startTime + duration
        var samples: [MotionSample] = []
        var time = startTime

        while time <= endTime {
            let phase = (time - startTime) / interval
            let pulse = sin(phase * 2 * .pi)
            var accel = AxisComponents()
            accel[keyPath: dominantAxis] = amplitude * pulse
            accel.x += 0.05 * sin(time * 1.7)
            accel.y += 0.03 * cos(time * 1.3)
            accel.z += 0.04 * sin(time * 0.9)

            samples.append(
                MotionSample(
                    userAccelerationX: accel.x,
                    userAccelerationY: accel.y,
                    userAccelerationZ: accel.z,
                    rotationRateX: 0,
                    rotationRateY: 0,
                    rotationRateZ: 0,
                    timestamp: time
                )
            )
            time += dt
        }

        return samples
    }

    func makeWatchSamples(
        duration: TimeInterval,
        sampleRate: Double,
        includeAccelerationConfirmation: Bool
    ) -> [MotionSample] {
        let dt = 1 / sampleRate
        let interval: TimeInterval = 0.42
        var samples: [MotionSample] = []
        var time: TimeInterval = 0

        while time <= duration {
            let phase = time / interval
            let gyroPulse = sin(phase * 2 * .pi)
            let accelPulsePhase = (time - 0.04) / interval
            let accelPulse = includeAccelerationConfirmation ? sin(accelPulsePhase * 2 * .pi) : 0

            samples.append(
                MotionSample(
                    userAccelerationX: 0.04 * sin(time * 0.8),
                    userAccelerationY: 0.4 * accelPulse,
                    userAccelerationZ: 0.03 * cos(time * 1.1),
                    rotationRateX: 0.15 * gyroPulse,
                    rotationRateY: 1.25 * gyroPulse,
                    rotationRateZ: 0.12 * gyroPulse,
                    timestamp: time
                )
            )
            time += dt
        }

        return samples
    }
}
