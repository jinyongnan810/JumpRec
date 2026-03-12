//
//  JumpDetectorNext.swift
//  JumpRec
//
//  Preserves the previous experimental detector for inspection.
//  It intentionally reuses the shared public enums and debug-state types from `JumpDetector.swift`.
//

import Foundation

public final class JumpDetectorNext {
    /// Tunable values are intentionally profile-specific, but the detector flow stays the same:
    /// 1) filter raw motion into short-window signals,
    /// 2) choose the most useful signal for the device profile,
    /// 3) detect local extrema above an adaptive threshold,
    /// 4) apply a refractory gate so one movement does not count multiple jumps.
    private struct Config {
        /// Number of seconds of recent filtered motion kept in memory.
        let rollingWindowDuration: TimeInterval
        /// Minimum allowed gap between accepted jumps.
        let refractoryInterval: TimeInterval
        /// Multiplier applied to MAD-derived adaptive thresholds.
        let thresholdMultiplier: Double
        /// Floor used when adaptive thresholds become too small.
        let minimumThreshold: Double
        /// Minimum short-window RMS energy required before an axis is considered meaningful.
        let minimumSignalRMS: Double
        /// Minimum local peak prominence required to accept an extremum candidate.
        let minimumProminence: Double
        /// Additional prominence scaling relative to the adaptive threshold.
        let prominenceThresholdRatio: Double
        /// Multiplier applied when checking overall acceleration magnitude support.
        let magnitudeSupportMultiplier: Double
        /// Time constant for removing slow acceleration drift.
        let baselineTimeConstant: TimeInterval
        /// Time constant for the short smoothing pass after baseline subtraction.
        let smoothingTimeConstant: TimeInterval
        /// Minimum ratio needed before switching the currently dominant axis.
        let axisSwitchRatio: Double
        /// Window used by watch-specific confirmation logic.
        let confirmationWindow: TimeInterval
        /// EWMA factor used to track recent accepted jump intervals for debugging.
        let expectedIntervalAlpha: Double

        static func profile(_ profile: JumpDeviceProfile) -> Config {
            switch profile {
            case .iPhonePocket:
                Config(
                    rollingWindowDuration: 1.2,
                    refractoryInterval: 0.25,
                    thresholdMultiplier: 0.35,
                    minimumThreshold: 0.055,
                    minimumSignalRMS: 0.06,
                    minimumProminence: 0.01,
                    prominenceThresholdRatio: 0.08,
                    magnitudeSupportMultiplier: 1.0,
                    baselineTimeConstant: 0.35,
                    smoothingTimeConstant: 0.05,
                    axisSwitchRatio: 1.2,
                    confirmationWindow: 0,
                    expectedIntervalAlpha: 0.22
                )
            case .headphones:
                Config(
                    rollingWindowDuration: 1.3,
                    refractoryInterval: 0.27,
                    thresholdMultiplier: 0.45,
                    minimumThreshold: 0.05,
                    minimumSignalRMS: 0.03,
                    minimumProminence: 0,
                    prominenceThresholdRatio: 0,
                    magnitudeSupportMultiplier: 0.85,
                    baselineTimeConstant: 0.40,
                    smoothingTimeConstant: 0.06,
                    axisSwitchRatio: 1.2,
                    confirmationWindow: 0,
                    expectedIntervalAlpha: 0.22
                )
            case .watch:
                Config(
                    rollingWindowDuration: 1.0,
                    refractoryInterval: 0.26,
                    thresholdMultiplier: 0.35,
                    minimumThreshold: 0.04,
                    minimumSignalRMS: 0.03,
                    minimumProminence: 0,
                    prominenceThresholdRatio: 0,
                    magnitudeSupportMultiplier: 1.0,
                    baselineTimeConstant: 0.28,
                    smoothingTimeConstant: 0.04,
                    axisSwitchRatio: 1.15,
                    confirmationWindow: 0.18,
                    expectedIntervalAlpha: 0.25
                )
            }
        }
    }

    /// One filtered sample held inside the rolling analysis window.
    private struct FilteredSample {
        /// Monotonic timestamp copied from `MotionSample`.
        let timestamp: TimeInterval
        /// High-pass + smoothed user acceleration vector.
        let accel: SIMD3<Double>
        /// High-pass + smoothed rotation-rate vector.
        let gyro: SIMD3<Double>
        /// Magnitude of the filtered acceleration vector.
        let accelMagnitude: Double
    }

    /// Public profile selected for this detector instance.
    public let profile: JumpDeviceProfile
    /// Enables verbose console logging while tuning the detector.
    public var debugLoggingEnabled = false
    /// Exposes the current detector interpretation for debugging UIs and logs.
    public private(set) var debugState: JumpDetectorDebugState

    /// Stores all per-profile constants used by this detector instance.
    private let config: Config

    /// Short rolling window of filtered samples.
    private var history: [FilteredSample] = []
    /// Low-frequency acceleration estimate removed from raw accel.
    private var accelBaseline = SIMD3<Double>(repeating: 0)
    /// Smoothed high-pass acceleration used for candidate finding.
    private var accelSmoothed = SIMD3<Double>(repeating: 0)
    /// Low-frequency gyro estimate removed from raw gyro.
    private var gyroBaseline = SIMD3<Double>(repeating: 0)
    /// Smoothed high-pass gyro used for signal inspection.
    private var gyroSmoothed = SIMD3<Double>(repeating: 0)

    /// Currently selected dominant axis for phone/headphone inspection.
    private var dominantAxis: JumpDetectorAxis?
    /// Currently selected extremum direction for the dominant axis.
    private var chosenPolarity: JumpDetectorPolarity?
    /// Timestamp of the last processed sample to derive `dt`.
    private var lastSampleTimestamp: TimeInterval?
    /// Timestamp of the last accepted jump event.
    private var lastAcceptedJumpTimestamp: TimeInterval?
    /// EWMA of recently accepted intervals, kept only for debugging.
    private var expectedInterval: TimeInterval?

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
            // Phone and headphones are acceleration-led. We continuously re-evaluate the dominant axis
            // so the detector can recover after the user repositions the device or resumes after a rest.
            updateAccelerationPattern()
            guard let axis = dominantAxis,
                  let polarity = chosenPolarity,
                  let candidate = accelerationCandidateTimestamp(for: axis, polarity: polarity)
            else {
                syncDebugState()
                return false
            }

            return acceptJump(at: candidate)

        case .watch:
            // Watch detection is impact-led. Wrist-only gyro motion created too many false counts in practice,
            // so the watch path now treats a sharp acceleration impact as the primary jump event.
            dominantAxis = .magnitude
            chosenPolarity = .positiveMagnitude
            guard let candidate = watchAccelerationCandidateTimestamp() else {
                syncDebugState()
                return false
            }

            return acceptWatchJump(at: candidate)
        }
    }

    public func reset() {
        history.removeAll(keepingCapacity: true)
        accelBaseline = .zero
        accelSmoothed = .zero
        gyroBaseline = .zero
        gyroSmoothed = .zero
        dominantAxis = nil
        chosenPolarity = nil
        lastSampleTimestamp = nil
        lastAcceptedJumpTimestamp = nil
        expectedInterval = nil
        debugState = JumpDetectorDebugState(profile: profile)
    }

    private func updateAccelerationPattern() {
        // Choose the axis with the strongest short-window energy. This keeps the detector orientation-agnostic
        // for pockets/headphones without requiring a fixed "up" axis.
        let axes: [(JumpDetectorAxis, [Double])] = [
            (.x, history.map { $0.accel.x }),
            (.y, history.map { $0.accel.y }),
            (.z, history.map { $0.accel.z }),
        ]

        let energies = Dictionary(uniqueKeysWithValues: axes.map { axis, values in
            (axis, rms(values))
        })

        let strongestAxis = energies.max { $0.value < $1.value }?.key
        guard let strongestAxis,
              let strongestEnergy = energies[strongestAxis],
              strongestEnergy >= config.minimumSignalRMS
        else {
            dominantAxis = nil
            chosenPolarity = nil
            return
        }

        if let currentAxis = dominantAxis,
           let currentEnergy = energies[currentAxis],
           currentEnergy > 0,
           strongestAxis != currentAxis,
           strongestEnergy / currentEnergy < config.axisSwitchRatio {
            // Keep the current axis unless the new one is clearly better.
        } else {
            dominantAxis = strongestAxis
        }

        guard let axis = dominantAxis,
              let values = axes.first(where: { $0.0 == axis })?.1
        else {
            return
        }

        chosenPolarity = selectPolarity(values: values)
    }

    private func selectPolarity(values: [Double]) -> JumpDetectorPolarity? {
        guard values.count >= 3 else { return nil }

        // Some placements produce a useful positive peak, others a useful negative trough.
        // We score both directly from recent extrema and keep whichever looks stronger.
        let threshold = adaptiveThreshold(for: values)
        var positiveScore = 0.0
        var negativeScore = 0.0

        for index in 1..<(values.count - 1) {
            let previous = values[index - 1]
            let current = values[index]
            let next = values[index + 1]

            if current > previous, current >= next, current >= threshold {
                positiveScore += current
            }
            if current < previous, current <= next, abs(current) >= threshold {
                negativeScore += abs(current)
            }
        }

        guard positiveScore > 0 || negativeScore > 0 else { return nil }
        return positiveScore >= negativeScore ? .positivePeak : .negativeTrough
    }

    private func accelerationCandidateTimestamp(
        for axis: JumpDetectorAxis,
        polarity: JumpDetectorPolarity
    ) -> TimeInterval? {
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

        return extremumCandidateTimestamp(
            values: values,
            timestamps: history.map(\.timestamp),
            polarity: polarity,
            thresholdMultiplier: 1.0
        )
    }

    private func extremumCandidateTimestamp(
        values: [Double],
        timestamps: [TimeInterval],
        polarity: JumpDetectorPolarity,
        thresholdMultiplier: Double
    ) -> TimeInterval? {
        guard values.count >= 3, timestamps.count == values.count else { return nil }

        // Thresholds are local and adaptive so quiet idle motion stays quiet while stronger jump motion
        // still registers without relying on one global number for every device and every user.
        let adaptiveBaseThreshold = adaptiveThreshold(for: values)
        let threshold = adaptiveBaseThreshold * thresholdMultiplier
        let previous = values[values.count - 2]
        let beforePrevious = values[values.count - 3]
        let current = values[values.count - 1]
        let candidateTimestamp = timestamps[timestamps.count - 2]
        let prominence = abs(previous - ((beforePrevious + current) * 0.5))
        let minimumProminence = max(
            config.minimumProminence,
            adaptiveBaseThreshold * config.prominenceThresholdRatio
        )

        switch polarity {
        case .positivePeak, .positiveMagnitude:
            guard previous > beforePrevious,
                  previous >= current,
                  previous >= threshold,
                  prominence >= minimumProminence
            else {
                return nil
            }
        case .negativeTrough:
            guard previous < beforePrevious,
                  previous <= current,
                  abs(previous) >= threshold,
                  prominence >= minimumProminence
            else {
                return nil
            }
        }

        return candidateTimestamp
    }

    private func watchAccelerationCandidateTimestamp() -> TimeInterval? {
        let values = history.map(\.accelMagnitude)
        let timestamps = history.map(\.timestamp)
        guard values.count >= 3, timestamps.count == values.count else { return nil }

        // The watch uses acceleration magnitude because actual jumps create a body-impact signature,
        // while hand-only movement is much more variable across axes.
        let threshold = adaptiveThreshold(for: values) * 0.65
        let previous = values[values.count - 2]
        let beforePrevious = values[values.count - 3]
        let current = values[values.count - 1]

        guard previous > beforePrevious,
              previous >= current,
              previous >= threshold
        else {
            return nil
        }

        return timestamps[timestamps.count - 2]
    }

    private func acceptJump(at timestamp: TimeInterval) -> Bool {
        guard isPastRefractory(timestamp) else {
            syncDebugState()
            return false
        }

        // For phone/headphones, a candidate on one axis still needs support from overall acceleration magnitude.
        // This suppresses small orientation-specific wiggles and "put down" artifacts that briefly spike one axis.
        guard hasAccelerationMagnitudeSupport(around: timestamp) else {
            syncDebugState()
            return false
        }

        registerAcceptedJump(at: timestamp)
        return true
    }

    private func acceptWatchJump(at timestamp: TimeInterval) -> Bool {
        guard isPastRefractory(timestamp) else {
            syncDebugState()
            return false
        }

        // Watch jumps are accepted directly from impact candidates. This is intentionally simpler than the earlier
        // gyro-led design because missing real jumps was worse than tolerating a small amount of extra noise.
        registerAcceptedJump(at: timestamp)
        return true
    }

    private func isPastRefractory(_ timestamp: TimeInterval) -> Bool {
        guard let lastAcceptedJumpTimestamp else { return true }
        return timestamp - lastAcceptedJumpTimestamp >= config.refractoryInterval
    }

    private func registerAcceptedJump(at timestamp: TimeInterval) {
        if let lastAcceptedJumpTimestamp {
            let interval = timestamp - lastAcceptedJumpTimestamp
            // `expectedInterval` is debug-only guidance right now. We keep updating it so cadence can still be
            // inspected in logs, but it no longer blocks counting after rests or speed changes.
            if let expectedInterval {
                self.expectedInterval =
                    (expectedInterval * (1 - config.expectedIntervalAlpha)) +
                    (interval * config.expectedIntervalAlpha)
            } else {
                expectedInterval = interval
            }
        }

        lastAcceptedJumpTimestamp = timestamp
        syncDebugState()

        if debugLoggingEnabled {
            print(
                "[JumpDetectorNext] profile=\(profile.rawValue) axis=\(dominantAxis?.rawValue ?? "nil") " +
                    "polarity=\(chosenPolarity?.rawValue ?? "nil") expected=\(expectedInterval.map { String(format: "%.3f", $0) } ?? "nil") " +
                    "accepted=\(String(format: "%.3f", timestamp))"
            )
        }
    }

    private func filter(_ sample: MotionSample) -> FilteredSample {
        let timestamp = sample.timestamp
        let dt = max(0.001, timestamp - (lastSampleTimestamp ?? timestamp))
        lastSampleTimestamp = timestamp

        // Filtering stays intentionally lightweight: a slow baseline subtraction acts like a high-pass filter,
        // then a short smoothing pass removes jitter without adding too much lag.
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

        let gyroBaselineAlpha = smoothingAlpha(dt: dt, timeConstant: config.baselineTimeConstant)
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
            accelMagnitude: magnitude(accelSmoothed)
        )
    }

    private func trimHistory(around timestamp: TimeInterval) {
        let cutoff = timestamp - config.rollingWindowDuration
        history.removeAll { $0.timestamp < cutoff }
    }

    private func hasAccelerationMagnitudeSupport(around timestamp: TimeInterval) -> Bool {
        let values = history.map(\.accelMagnitude)
        let timestamps = history.map(\.timestamp)
        guard !values.isEmpty else { return false }

        // This support check is the main false-positive guard for phone/headphones.
        // We only accept an axis extremum if the total acceleration magnitude also looks meaningful nearby.
        let threshold = adaptiveThreshold(for: values) * config.magnitudeSupportMultiplier
        return zip(timestamps, values).contains { sampleTimestamp, value in
            abs(sampleTimestamp - timestamp) <= 0.08 && value >= threshold
        }
    }

    private func syncDebugState() {
        debugState = JumpDetectorDebugState(
            profile: profile,
            dominantAxis: dominantAxis,
            chosenPolarity: chosenPolarity,
            rhythmLocked: false,
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
