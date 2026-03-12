//
//  JumpDetector.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/02/28.
//

import Foundation

public enum JumpDeviceProfile: String, Sendable {
    case iPhonePocket
    case headphones
    case watch
}

public enum JumpDetectorAxis: String, Sendable {
    case x
    case y
    case z
    case magnitude
}

public enum JumpDetectorPolarity: String, Sendable {
    case positivePeak
    case negativeTrough
    case positiveMagnitude
}

public struct JumpDetectorDebugState: Sendable {
    public let profile: JumpDeviceProfile
    public let dominantAxis: JumpDetectorAxis?
    public let chosenPolarity: JumpDetectorPolarity?
    public let rhythmLocked: Bool
    public let expectedInterval: TimeInterval?
    public let lastAcceptedJumpTimestamp: TimeInterval?

    public init(
        profile: JumpDeviceProfile,
        dominantAxis: JumpDetectorAxis? = nil,
        chosenPolarity: JumpDetectorPolarity? = nil,
        rhythmLocked: Bool = false,
        expectedInterval: TimeInterval? = nil,
        lastAcceptedJumpTimestamp: TimeInterval? = nil
    ) {
        self.profile = profile
        self.dominantAxis = dominantAxis
        self.chosenPolarity = chosenPolarity
        self.rhythmLocked = rhythmLocked
        self.expectedInterval = expectedInterval
        self.lastAcceptedJumpTimestamp = lastAcceptedJumpTimestamp
    }
}

public final class JumpDetector {
    private struct Config {
        let warmupDuration: TimeInterval
        let rollingWindowDuration: TimeInterval
        let minInterval: TimeInterval
        let maxInterval: TimeInterval
        let refractoryInterval: TimeInterval
        let cadenceTolerance: Double
        let requireRhythmLock: Bool
        let minimumStableCycles: Int
        let thresholdMultiplier: Double
        let minimumThreshold: Double
        let baselineTimeConstant: TimeInterval
        let smoothingTimeConstant: TimeInterval
        let confirmationWindow: TimeInterval
        let axisSwitchRatio: Double
        let expectedIntervalAlpha: Double
        let rhythmLockTolerance: Double

        static func profile(_ profile: JumpDeviceProfile) -> Config {
            switch profile {
            case .iPhonePocket:
                Config(
                    warmupDuration: 1.5,
                    rollingWindowDuration: 1.8,
                    minInterval: 0.25,
                    maxInterval: 0.9,
                    refractoryInterval: 0.32,
                    cadenceTolerance: 0.35,
                    requireRhythmLock: false,
                    minimumStableCycles: 2,
                    thresholdMultiplier: 0.6,
                    minimumThreshold: 0.08,
                    baselineTimeConstant: 0.45,
                    smoothingTimeConstant: 0.08,
                    confirmationWindow: 0,
                    axisSwitchRatio: 1.35,
                    expectedIntervalAlpha: 0.2,
                    rhythmLockTolerance: 0.16
                )
            case .headphones:
                Config(
                    warmupDuration: 2.0,
                    rollingWindowDuration: 2.2,
                    minInterval: 0.28,
                    maxInterval: 0.9,
                    refractoryInterval: 0.34,
                    cadenceTolerance: 0.30,
                    requireRhythmLock: true,
                    minimumStableCycles: 3,
                    thresholdMultiplier: 0.7,
                    minimumThreshold: 0.06,
                    baselineTimeConstant: 0.55,
                    smoothingTimeConstant: 0.10,
                    confirmationWindow: 0,
                    axisSwitchRatio: 1.4,
                    expectedIntervalAlpha: 0.18,
                    rhythmLockTolerance: 0.12
                )
            case .watch:
                Config(
                    warmupDuration: 1.0,
                    rollingWindowDuration: 1.6,
                    minInterval: 0.25,
                    maxInterval: 0.9,
                    refractoryInterval: 0.30,
                    cadenceTolerance: 0.33,
                    requireRhythmLock: false,
                    minimumStableCycles: 2,
                    thresholdMultiplier: 0.65,
                    minimumThreshold: 0.10,
                    baselineTimeConstant: 0.35,
                    smoothingTimeConstant: 0.06,
                    confirmationWindow: 0.18,
                    axisSwitchRatio: 1.25,
                    expectedIntervalAlpha: 0.22,
                    rhythmLockTolerance: 0.18
                )
            }
        }
    }

    private struct FilteredSample {
        let timestamp: TimeInterval
        let accel: SIMD3<Double>
        let gyro: SIMD3<Double>
        let accelMagnitude: Double
        let gyroMagnitude: Double
    }

    private struct CandidatePattern {
        let axis: JumpDetectorAxis
        let polarity: JumpDetectorPolarity
        let events: [TimeInterval]
        let energy: Double

        var score: Double {
            guard events.count >= 3 else { return 0 }
            let intervals = zip(events.dropFirst(), events).map { newer, older in
                newer - older
            }
            let validIntervals = intervals.filter { $0 >= 0.15 }
            guard validIntervals.count >= 2 else { return 0 }
            let mean = validIntervals.reduce(0, +) / Double(validIntervals.count)
            guard mean > 0 else { return 0 }
            let variance = validIntervals.reduce(0) { partialResult, interval in
                partialResult + pow(interval - mean, 2)
            } / Double(validIntervals.count)
            let stabilityPenalty = 1 / (1 + sqrt(variance) / mean)
            return Double(validIntervals.count) * stabilityPenalty * max(0.2, energy)
        }
    }

    public let profile: JumpDeviceProfile
    public var debugLoggingEnabled = false
    public private(set) var debugState: JumpDetectorDebugState

    private let config: Config

    private var history: [FilteredSample] = []
    private var accelBaseline = SIMD3<Double>(repeating: 0)
    private var accelSmoothed = SIMD3<Double>(repeating: 0)
    private var gyroBaseline = SIMD3<Double>(repeating: 0)
    private var gyroSmoothed = SIMD3<Double>(repeating: 0)

    private var startTimestamp: TimeInterval?
    private var lastSampleTimestamp: TimeInterval?
    private var dominantAxis: JumpDetectorAxis?
    private var chosenPolarity: JumpDetectorPolarity?
    private var lastCandidateTimestamp: TimeInterval?
    private var lastAcceptedJumpTimestamp: TimeInterval?
    private var expectedInterval: TimeInterval?
    private var acceptedJumpCount = 0
    private var rhythmCandidateIntervals: [TimeInterval] = []
    private var rhythmLocked = false
    private var recentAccelerationCandidates: [TimeInterval] = []

    public init(profile: JumpDeviceProfile = .iPhonePocket) {
        self.profile = profile
        config = .profile(profile)
        debugState = JumpDetectorDebugState(profile: profile)
    }

    public func processMotionSample(_ sample: MotionSample) -> Bool {
        let filteredSample = filter(sample)
        history.append(filteredSample)
        trimHistory(around: filteredSample.timestamp)

        switch profile {
        case .iPhonePocket, .headphones:
            return processAccelerationProfile()
        case .watch:
            registerWatchAccelerationCandidateIfNeeded()
            return processWatchProfile()
        }
    }

    public func reset() {
        history.removeAll(keepingCapacity: true)
        accelBaseline = .zero
        accelSmoothed = .zero
        gyroBaseline = .zero
        gyroSmoothed = .zero
        startTimestamp = nil
        lastSampleTimestamp = nil
        dominantAxis = nil
        chosenPolarity = nil
        lastCandidateTimestamp = nil
        lastAcceptedJumpTimestamp = nil
        expectedInterval = nil
        acceptedJumpCount = 0
        rhythmCandidateIntervals.removeAll(keepingCapacity: false)
        recentAccelerationCandidates.removeAll(keepingCapacity: false)
        rhythmLocked = false
        debugState = JumpDetectorDebugState(profile: profile)
    }

    private func processAccelerationProfile() -> Bool {
        guard let currentSample = history.last else { return false }
        let elapsed = currentSample.timestamp - (startTimestamp ?? currentSample.timestamp)

        if dominantAxis == nil || elapsed <= config.warmupDuration {
            let pattern = selectDominantAccelerationPattern()
            dominantAxis = pattern?.axis
            chosenPolarity = pattern?.polarity
        }

        syncDebugState()

        guard elapsed >= config.warmupDuration,
              let axis = dominantAxis,
              let polarity = chosenPolarity,
              let candidateTimestamp = accelerationExtremumCandidate(for: axis, polarity: polarity)
        else {
            return false
        }

        return handleCandidate(timestamp: candidateTimestamp)
    }

    private func processWatchProfile() -> Bool {
        guard let currentSample = history.last else { return false }
        let elapsed = currentSample.timestamp - (startTimestamp ?? currentSample.timestamp)

        if dominantAxis == nil || elapsed <= config.warmupDuration {
            let pattern = selectDominantGyroPattern()
            dominantAxis = pattern?.axis
            chosenPolarity = pattern?.polarity
        }
        syncDebugState()

        guard elapsed >= config.warmupDuration,
              let axis = dominantAxis,
              let polarity = chosenPolarity,
              let gyroCandidateTimestamp = gyroExtremumCandidate(for: axis, polarity: polarity)
        else {
            return false
        }

        let confirmed = recentAccelerationCandidates.contains { candidateTimestamp in
            abs(candidateTimestamp - gyroCandidateTimestamp) <= config.confirmationWindow
        }
        guard confirmed else {
            if debugLoggingEnabled {
                print(
                    "[JumpDetector] watchCandidateRejected gyro=\(String(format: "%.3f", gyroCandidateTimestamp)) " +
                        "accelCandidates=\(recentAccelerationCandidates.map { String(format: "%.3f", $0) })"
                )
            }
            return false
        }

        recentAccelerationCandidates.removeAll {
            gyroCandidateTimestamp - $0 > config.confirmationWindow
        }

        return handleCandidate(timestamp: gyroCandidateTimestamp)
    }

    private func handleCandidate(timestamp: TimeInterval) -> Bool {
        if let lastCandidateTimestamp, timestamp <= lastCandidateTimestamp {
            return false
        }

        let intervalFromPreviousCandidate = lastCandidateTimestamp.map { timestamp - $0 }
        lastCandidateTimestamp = timestamp

        if let candidateInterval = intervalFromPreviousCandidate {
            updateRhythmLock(with: candidateInterval)
        }

        guard !config.requireRhythmLock || rhythmLocked else {
            syncDebugState()
            return false
        }

        guard acceptCandidate(timestamp: timestamp) else {
            syncDebugState()
            return false
        }

        lastAcceptedJumpTimestamp = timestamp
        acceptedJumpCount += 1
        syncDebugState()

        if debugLoggingEnabled {
            print(
                "[JumpDetector] profile=\(profile.rawValue) axis=\(dominantAxis?.rawValue ?? "nil") " +
                    "polarity=\(chosenPolarity?.rawValue ?? "nil") locked=\(rhythmLocked) " +
                    "expected=\(expectedInterval.map { String(format: "%.3f", $0) } ?? "nil") " +
                    "accepted=\(String(format: "%.3f", timestamp))"
            )
        }

        return true
    }

    private func acceptCandidate(timestamp: TimeInterval) -> Bool {
        if let lastAcceptedJumpTimestamp {
            let interval = timestamp - lastAcceptedJumpTimestamp

            guard interval >= config.refractoryInterval,
                  interval >= config.minInterval,
                  interval <= config.maxInterval
            else {
                return false
            }

            if acceptedJumpCount >= 3,
               let expectedInterval {
                let deltaRatio = abs(interval - expectedInterval) / expectedInterval
                guard deltaRatio <= config.cadenceTolerance else {
                    return false
                }
            }

            if let expectedInterval {
                self.expectedInterval =
                    (expectedInterval * (1 - config.expectedIntervalAlpha)) +
                    (interval * config.expectedIntervalAlpha)
            } else {
                expectedInterval = interval
            }
        }

        return true
    }

    private func updateRhythmLock(with interval: TimeInterval) {
        guard interval >= config.minInterval, interval <= config.maxInterval else {
            rhythmCandidateIntervals.removeAll(keepingCapacity: true)
            rhythmLocked = false
            return
        }

        rhythmCandidateIntervals.append(interval)
        if rhythmCandidateIntervals.count > config.minimumStableCycles {
            rhythmCandidateIntervals.removeFirst(rhythmCandidateIntervals.count - config.minimumStableCycles)
        }

        guard rhythmCandidateIntervals.count == config.minimumStableCycles else {
            rhythmLocked = false
            return
        }

        let mean = rhythmCandidateIntervals.reduce(0, +) / Double(rhythmCandidateIntervals.count)
        guard mean > 0 else {
            rhythmLocked = false
            return
        }

        let maxDeviationRatio = rhythmCandidateIntervals
            .map { abs($0 - mean) / mean }
            .max() ?? 1
        rhythmLocked = maxDeviationRatio <= config.rhythmLockTolerance
    }

    private func selectDominantAccelerationPattern() -> CandidatePattern? {
        let samples = history
        guard samples.count >= 5 else { return nil }

        let axisCandidates: [(JumpDetectorAxis, [Double])] = [
            (.x, samples.map { $0.accel.x }),
            (.y, samples.map { $0.accel.y }),
            (.z, samples.map { $0.accel.z }),
        ]

        let currentEnergyByAxis = Dictionary(uniqueKeysWithValues: axisCandidates.map { axis, values in
            (axis, rms(values))
        })

        let selectedAxis: JumpDetectorAxis
        if let dominantAxis,
           let currentEnergy = currentEnergyByAxis[dominantAxis],
           currentEnergy > 0 {
            let strongest = currentEnergyByAxis.max { $0.value < $1.value }
            if let strongest, strongest.value / currentEnergy > config.axisSwitchRatio {
                selectedAxis = strongest.key
            } else {
                selectedAxis = dominantAxis
            }
        } else {
            selectedAxis = currentEnergyByAxis.max { $0.value < $1.value }?.key ?? .y
        }

        let values = axisCandidates.first { $0.0 == selectedAxis }?.1 ?? []
        let timestamps = samples.map(\.timestamp)
        let threshold = adaptiveThreshold(for: values)
        let positiveEvents = detectExtremaEvents(
            values: values,
            timestamps: timestamps,
            polarity: .positivePeak,
            threshold: threshold
        )
        let negativeEvents = detectExtremaEvents(
            values: values,
            timestamps: timestamps,
            polarity: .negativeTrough,
            threshold: threshold
        )

        let positive = CandidatePattern(
            axis: selectedAxis,
            polarity: .positivePeak,
            events: positiveEvents,
            energy: currentEnergyByAxis[selectedAxis] ?? 0
        )
        let negative = CandidatePattern(
            axis: selectedAxis,
            polarity: .negativeTrough,
            events: negativeEvents,
            energy: currentEnergyByAxis[selectedAxis] ?? 0
        )

        return [positive, negative].max { $0.score < $1.score }
    }

    private func selectDominantGyroPattern() -> CandidatePattern? {
        let samples = history
        guard samples.count >= 5 else { return nil }

        let axisCandidates: [(JumpDetectorAxis, [Double])] = [
            (.x, samples.map { $0.gyro.x }),
            (.y, samples.map { $0.gyro.y }),
            (.z, samples.map { $0.gyro.z }),
        ]

        let currentEnergyByAxis = Dictionary(uniqueKeysWithValues: axisCandidates.map { axis, values in
            (axis, rms(values))
        })

        let selectedAxis: JumpDetectorAxis
        if let dominantAxis,
           let currentEnergy = currentEnergyByAxis[dominantAxis],
           currentEnergy > 0 {
            let strongest = currentEnergyByAxis.max { $0.value < $1.value }
            if let strongest, strongest.value / currentEnergy > config.axisSwitchRatio {
                selectedAxis = strongest.key
            } else {
                selectedAxis = dominantAxis
            }
        } else {
            selectedAxis = currentEnergyByAxis.max { $0.value < $1.value }?.key ?? .y
        }

        let values = axisCandidates.first { $0.0 == selectedAxis }?.1 ?? []
        let timestamps = samples.map(\.timestamp)
        let threshold = adaptiveThreshold(for: values)
        let positiveEvents = detectExtremaEvents(
            values: values,
            timestamps: timestamps,
            polarity: .positivePeak,
            threshold: threshold
        )
        let negativeEvents = detectExtremaEvents(
            values: values,
            timestamps: timestamps,
            polarity: .negativeTrough,
            threshold: threshold
        )

        let positive = CandidatePattern(
            axis: selectedAxis,
            polarity: .positivePeak,
            events: positiveEvents,
            energy: currentEnergyByAxis[selectedAxis] ?? 0
        )
        let negative = CandidatePattern(
            axis: selectedAxis,
            polarity: .negativeTrough,
            events: negativeEvents,
            energy: currentEnergyByAxis[selectedAxis] ?? 0
        )

        return [positive, negative].max { $0.score < $1.score }
    }

    private func accelerationExtremumCandidate(
        for axis: JumpDetectorAxis,
        polarity: JumpDetectorPolarity
    ) -> TimeInterval? {
        guard history.count >= 3 else { return nil }

        let values = history.map { sample -> Double in
            switch axis {
            case .x:
                sample.accel.x
            case .y:
                sample.accel.y
            case .z:
                sample.accel.z
            case .magnitude:
                sample.accelMagnitude
            }
        }
        let timestamps = history.map(\.timestamp)
        let threshold = adaptiveThreshold(for: values)

        let previous = values[history.count - 2]
        let beforePrevious = values[history.count - 3]
        let current = values[history.count - 1]
        let candidateTimestamp = timestamps[history.count - 2]

        switch polarity {
        case .positivePeak, .positiveMagnitude:
            guard previous > beforePrevious,
                  previous >= current,
                  previous >= threshold
            else {
                return nil
            }
        case .negativeTrough:
            guard previous < beforePrevious,
                  previous <= current,
                  abs(previous) >= threshold
            else {
                return nil
            }
        }

        return candidateTimestamp
    }

    private func registerWatchAccelerationCandidateIfNeeded() {
        guard history.count >= 3 else { return }

        let values = history.map(\.accelMagnitude)
        let timestamps = history.map(\.timestamp)
        let threshold = adaptiveThreshold(for: values)
        let previous = values[history.count - 2]
        let beforePrevious = values[history.count - 3]
        let current = values[history.count - 1]
        let candidateTimestamp = timestamps[history.count - 2]

        guard previous > beforePrevious,
              previous >= current,
              previous >= threshold
        else {
            return
        }

        if let last = recentAccelerationCandidates.last, candidateTimestamp - last < 0.08 {
            return
        }

        recentAccelerationCandidates.append(candidateTimestamp)
        if debugLoggingEnabled {
            print("[JumpDetector] watchAccelCandidate=\(String(format: "%.3f", candidateTimestamp))")
        }
        recentAccelerationCandidates.removeAll {
            candidateTimestamp - $0 > max(config.confirmationWindow, 0.3)
        }
    }

    private func gyroExtremumCandidate(
        for axis: JumpDetectorAxis,
        polarity: JumpDetectorPolarity
    ) -> TimeInterval? {
        guard history.count >= 3 else { return nil }

        let values = history.map { sample -> Double in
            switch axis {
            case .x:
                sample.gyro.x
            case .y:
                sample.gyro.y
            case .z:
                sample.gyro.z
            case .magnitude:
                sample.gyroMagnitude
            }
        }
        let timestamps = history.map(\.timestamp)
        let threshold = adaptiveThreshold(for: values)
        let previous = values[history.count - 2]
        let beforePrevious = values[history.count - 3]
        let current = values[history.count - 1]
        let candidateTimestamp = timestamps[history.count - 2]

        switch polarity {
        case .positivePeak, .positiveMagnitude:
            guard previous > beforePrevious,
                  previous >= current,
                  previous >= threshold
            else {
                return nil
            }
        case .negativeTrough:
            guard previous < beforePrevious,
                  previous <= current,
                  abs(previous) >= threshold
            else {
                return nil
            }
        }

        if debugLoggingEnabled {
            print(
                "[JumpDetector] watchGyroCandidate axis=\(axis.rawValue) polarity=\(polarity.rawValue) " +
                    "time=\(String(format: "%.3f", candidateTimestamp))"
            )
        }

        return candidateTimestamp
    }

    private func detectExtremaEvents(
        values: [Double],
        timestamps: [TimeInterval],
        polarity: JumpDetectorPolarity,
        threshold: Double
    ) -> [TimeInterval] {
        guard values.count == timestamps.count, values.count >= 3 else { return [] }

        var events: [TimeInterval] = []
        var lastEventTimestamp: TimeInterval?

        for index in 1..<(values.count - 1) {
            let previous = values[index - 1]
            let current = values[index]
            let next = values[index + 1]
            let timestamp = timestamps[index]

            let isExtremum: Bool
            switch polarity {
            case .positivePeak, .positiveMagnitude:
                isExtremum = current > previous && current >= next && current >= threshold
            case .negativeTrough:
                isExtremum = current < previous && current <= next && abs(current) >= threshold
            }

            guard isExtremum else { continue }

            if let lastEventTimestamp,
               timestamp - lastEventTimestamp < config.refractoryInterval * 0.7 {
                continue
            }

            events.append(timestamp)
            lastEventTimestamp = timestamp
        }

        return events
    }

    private func filter(_ sample: MotionSample) -> FilteredSample {
        let timestamp = sample.timestamp
        if startTimestamp == nil {
            startTimestamp = timestamp
        }

        let dt = max(0.001, timestamp - (lastSampleTimestamp ?? timestamp))
        lastSampleTimestamp = timestamp

        let rawAccel = SIMD3<Double>(
            sample.userAccelerationX,
            sample.userAccelerationY,
            sample.userAccelerationZ
        )
        let rawGyro = SIMD3<Double>(
            sample.rotationRateX,
            sample.rotationRateY,
            sample.rotationRateZ
        )

        let accelBaselineAlpha = smoothingAlpha(dt: dt, timeConstant: config.baselineTimeConstant)
        accelBaseline = accelBaseline + ((rawAccel - accelBaseline) * accelBaselineAlpha)

        let gyroBaselineAlpha = smoothingAlpha(dt: dt, timeConstant: config.baselineTimeConstant * 0.8)
        gyroBaseline = gyroBaseline + ((rawGyro - gyroBaseline) * gyroBaselineAlpha)

        let accelHighPass = rawAccel - accelBaseline
        let gyroHighPass = rawGyro - gyroBaseline

        let smoothing = smoothingAlpha(dt: dt, timeConstant: config.smoothingTimeConstant)
        accelSmoothed = accelSmoothed + ((accelHighPass - accelSmoothed) * smoothing)
        gyroSmoothed = gyroSmoothed + ((gyroHighPass - gyroSmoothed) * smoothing)

        return FilteredSample(
            timestamp: timestamp,
            accel: accelSmoothed,
            gyro: gyroSmoothed,
            accelMagnitude: magnitude(accelSmoothed),
            gyroMagnitude: magnitude(gyroSmoothed)
        )
    }

    private func trimHistory(around timestamp: TimeInterval) {
        let cutoff = timestamp - max(config.rollingWindowDuration, config.warmupDuration + 0.3)
        history.removeAll { $0.timestamp < cutoff }
        recentAccelerationCandidates.removeAll { timestamp - $0 > max(config.confirmationWindow, 0.3) }
    }

    private func syncDebugState() {
        debugState = JumpDetectorDebugState(
            profile: profile,
            dominantAxis: dominantAxis,
            chosenPolarity: chosenPolarity,
            rhythmLocked: rhythmLocked,
            expectedInterval: expectedInterval,
            lastAcceptedJumpTimestamp: lastAcceptedJumpTimestamp
        )
    }

    private func adaptiveThreshold(for values: [Double]) -> Double {
        let magnitudes = values.map(abs)
        let medianMagnitude = median(of: magnitudes)
        let deviations = magnitudes.map { abs($0 - medianMagnitude) }
        let mad = median(of: deviations)
        return max(config.minimumThreshold, medianMagnitude + (mad * config.thresholdMultiplier))
    }

    private func smoothingAlpha(dt: TimeInterval, timeConstant: TimeInterval) -> Double {
        guard timeConstant > 0 else { return 1 }
        return min(1, dt / (timeConstant + dt))
    }

    private func rms(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sumSquares = values.reduce(0) { partialResult, value in
            partialResult + (value * value)
        }
        return sqrt(sumSquares / Double(values.count))
    }

    private func median(of values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private func magnitude(_ value: SIMD3<Double>) -> Double {
        sqrt((value.x * value.x) + (value.y * value.y) + (value.z * value.z))
    }
}
