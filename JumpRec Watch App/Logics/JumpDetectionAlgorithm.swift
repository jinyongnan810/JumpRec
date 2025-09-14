//
//  JumpDetectionAlgorithm.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import Accelerate
import CoreMotion
import Foundation

/// Advanced jump detection algorithm with signal processing
class JumpDetectionAlgorithm {
    // MARK: - Algorithm Parameters

    struct Parameters {
        // Thresholds
        var minPeakThreshold: Double = 1.5 // Minimum G-force for jump
        var maxPeakThreshold: Double = 4.0 // Maximum reasonable G-force
        var verticalRatio: Double = 0.7 // Vertical component ratio

        // Timing
        var minJumpDuration: TimeInterval = 0.15 // Minimum airtime
        var maxJumpDuration: TimeInterval = 0.8 // Maximum airtime
        var debounceTime: TimeInterval = 0.3 // Prevent double counting

        // Pattern Recognition
        var usePeakValleyDetection: Bool = true
        var useFrequencyAnalysis: Bool = true
        var patternMatchThreshold: Double = 0.75
    }

    // MARK: - State Machine

    enum JumpPhase {
        case ground // Standing/preparing
        case compression // Bending knees before jump
        case takeoff // Pushing off ground
        case flight // In the air
        case landing // Coming back down

        var expectedAcceleration: ClosedRange<Double> {
            switch self {
            case .ground: -0.2 ... 0.2
            case .compression: -0.5 ... -0.1
            case .takeoff: 1.5 ... 4.0
            case .flight: -0.3 ... 0.3
            case .landing: 1.0 ... 3.0
            }
        }
    }

    // MARK: - Properties

    private var parameters = Parameters()
    private var currentPhase: JumpPhase = .ground
    private var phaseStartTime: TimeInterval = 0
    private var jumpStartTime: TimeInterval = 0

    // Signal Processing
    private var signalBuffer: [Double] = []
    private let bufferSize = 100 // 1 second at 100Hz
    private var filteredSignal: [Double] = []

    // Statistics
    private var jumpPattern: [JumpPhase] = []
    private var validJumpCount = 0
    private var falsePositiveCount = 0

    // MARK: - Main Detection Method

    /// Process acceleration data and detect jumps
    func processAcceleration(_ data: AccelerationData) -> JumpDetectionResult {
        // Add to buffer
        updateBuffer(data.totalAcceleration)

        // Apply filters
        let filtered = applyFilters(to: signalBuffer)

        // Update state machine
        let phaseChange = updatePhase(
            acceleration: data.totalAcceleration,
            vertical: data.verticalAcceleration,
            timestamp: data.timestamp
        )

        // Detect jump completion
        if phaseChange, currentPhase == .ground {
            return evaluateJumpCompletion()
        }

        return JumpDetectionResult(
            isJump: false,
            confidence: 0,
            phase: currentPhase
        )
    }

    // MARK: - Signal Processing

    private func updateBuffer(_ value: Double) {
        signalBuffer.append(value)
        if signalBuffer.count > bufferSize {
            signalBuffer.removeFirst()
        }
    }

    private func applyFilters(to signal: [Double]) -> [Double] {
        guard signal.count > 10 else { return signal }

        var filtered = signal

        // 1. Moving average filter (smoothing)
        filtered = movingAverageFilter(filtered, windowSize: 3)

        // 2. High-pass filter (remove DC component/gravity)
        filtered = highPassFilter(filtered, cutoffFrequency: 0.5)

        // 3. Median filter (remove spikes)
        filtered = medianFilter(filtered, windowSize: 5)

        filteredSignal = filtered
        return filtered
    }

    private func movingAverageFilter(_ signal: [Double], windowSize: Int) -> [Double] {
        guard signal.count >= windowSize else { return signal }

        var filtered: [Double] = []
        for i in 0 ..< signal.count {
            let start = max(0, i - windowSize / 2)
            let end = min(signal.count, i + windowSize / 2 + 1)
            let window = Array(signal[start ..< end])
            let average = window.reduce(0, +) / Double(window.count)
            filtered.append(average)
        }
        return filtered
    }

    private func highPassFilter(_ signal: [Double], cutoffFrequency: Double) -> [Double] {
        guard signal.count > 1 else { return signal }

        let rc = 1.0 / (2.0 * .pi * cutoffFrequency)
        let dt = 0.01 // 100Hz sampling
        let alpha = rc / (rc + dt)

        var filtered: [Double] = [signal[0]]
        for i in 1 ..< signal.count {
            let value = alpha * (filtered[i - 1] + signal[i] - signal[i - 1])
            filtered.append(value)
        }
        return filtered
    }

    private func medianFilter(_ signal: [Double], windowSize: Int) -> [Double] {
        guard signal.count >= windowSize else { return signal }

        var filtered: [Double] = []
        for i in 0 ..< signal.count {
            let start = max(0, i - windowSize / 2)
            let end = min(signal.count, i + windowSize / 2 + 1)
            let window = Array(signal[start ..< end]).sorted()
            let median = window[window.count / 2]
            filtered.append(median)
        }
        return filtered
    }

    // MARK: - Peak Detection

    private func findPeaks(in signal: [Double], threshold: Double) -> [Int] {
        guard signal.count > 2 else { return [] }

        var peaks: [Int] = []

        for i in 1 ..< (signal.count - 1) {
            let prev = signal[i - 1]
            let curr = signal[i]
            let next = signal[i + 1]

            // Local maximum above threshold
            if curr > prev, curr > next, curr > threshold {
                peaks.append(i)
            }
        }

        // Remove peaks too close together
        return filterClosePeaks(peaks, minDistance: 30) // 300ms at 100Hz
    }

    private func filterClosePeaks(_ peaks: [Int], minDistance: Int) -> [Int] {
        guard peaks.count > 1 else { return peaks }

        var filtered: [Int] = [peaks[0]]

        for i in 1 ..< peaks.count {
            if peaks[i] - filtered.last! >= minDistance {
                filtered.append(peaks[i])
            }
        }

        return filtered
    }

    // MARK: - State Machine

    private func updatePhase(acceleration: Double,
                             vertical: Double,
                             timestamp: TimeInterval) -> Bool
    {
        let previousPhase = currentPhase

        switch currentPhase {
        case .ground:
            // Look for compression (negative acceleration)
            if vertical < -0.2, acceleration < 0.8 {
                currentPhase = .compression
                phaseStartTime = timestamp
            }

        case .compression:
            // Look for takeoff (sudden positive acceleration)
            if vertical > parameters.minPeakThreshold {
                currentPhase = .takeoff
                jumpStartTime = timestamp
            } else if timestamp - phaseStartTime > 0.5 {
                // Too long in compression, reset
                currentPhase = .ground
            }

        case .takeoff:
            // Wait for peak and transition to flight
            if acceleration < 0.5 {
                currentPhase = .flight
            }

        case .flight:
            // Look for landing (positive acceleration)
            if acceleration > 1.0, vertical > 0.5 {
                currentPhase = .landing
            } else if timestamp - jumpStartTime > parameters.maxJumpDuration {
                // Too long in flight, likely false positive
                currentPhase = .ground
                falsePositiveCount += 1
            }

        case .landing:
            // Return to ground state
            if acceleration < 1.2 {
                currentPhase = .ground
            }
        }

        // Record phase transition
        if currentPhase != previousPhase {
            jumpPattern.append(currentPhase)
            return true
        }

        return false
    }

    // MARK: - Jump Validation

    private func evaluateJumpCompletion() -> JumpDetectionResult {
        // Check if we have a complete jump pattern
        let expectedPattern: [JumpPhase] = [.compression, .takeoff, .flight, .landing, .ground]

        // Calculate pattern match score
        let matchScore = calculatePatternMatch(jumpPattern, expected: expectedPattern)

        // Validate jump characteristics
        let isValid = validateJump(matchScore: matchScore)

        // Clear pattern for next jump
        jumpPattern.removeAll()

        if isValid {
            validJumpCount += 1
            return JumpDetectionResult(
                isJump: true,
                confidence: matchScore,
                phase: .ground,
                jumpCharacteristics: analyzeJumpCharacteristics()
            )
        }

        return JumpDetectionResult(
            isJump: false,
            confidence: matchScore,
            phase: .ground
        )
    }

    private func calculatePatternMatch(_ actual: [JumpPhase],
                                       expected: [JumpPhase]) -> Double
    {
        guard !actual.isEmpty else { return 0 }

        // Simple pattern matching - could be enhanced with DTW
        var matches = 0
        let minLength = min(actual.count, expected.count)

        for i in 0 ..< minLength {
            if actual[actual.count - minLength + i] == expected[expected.count - minLength + i] {
                matches += 1
            }
        }

        return Double(matches) / Double(expected.count)
    }

    private func validateJump(matchScore: Double) -> Bool {
        // Multiple validation criteria
        let criteria = [
            matchScore > parameters.patternMatchThreshold,
            jumpPattern.contains(.takeoff),
            jumpPattern.contains(.flight),
            !jumpPattern.isEmpty,
        ]

        // Need at least 3 criteria met
        let metCriteria = criteria.filter(\.self).count
        return metCriteria >= 3
    }

    // MARK: - Analysis

    private func analyzeJumpCharacteristics() -> JumpCharacteristics {
        guard let maxAccel = filteredSignal.max() else {
            return JumpCharacteristics()
        }

        return JumpCharacteristics(
            peakAcceleration: maxAccel,
            airTime: estimateAirTime(),
            jumpHeight: estimateJumpHeight(peakAcceleration: maxAccel),
            quality: assessJumpQuality()
        )
    }

    private func estimateAirTime() -> TimeInterval {
        // Based on phase durations
        let flightPhases = jumpPattern.filter { $0 == .flight }
        return Double(flightPhases.count) * 0.01 // Samples * sampling period
    }

    private func estimateJumpHeight(peakAcceleration: Double) -> Double {
        // Simplified physics model
        // h = (v²) / (2g), where v = a*t
        let takeoffVelocity = peakAcceleration * 9.8 * 0.1 // Rough estimate
        return (takeoffVelocity * takeoffVelocity) / (2 * 9.8) * 100 // Convert to cm
    }

    private func assessJumpQuality() -> JumpQuality {
        let ratio = Double(validJumpCount) / Double(validJumpCount + falsePositiveCount)

        if ratio > 0.9 { return .excellent }
        if ratio > 0.7 { return .good }
        if ratio > 0.5 { return .fair }
        return .poor
    }
}

// MARK: - Supporting Types

struct AccelerationData {
    let totalAcceleration: Double
    let verticalAcceleration: Double
    let horizontalAcceleration: Double
    let timestamp: TimeInterval
}

struct JumpDetectionResult {
    let isJump: Bool
    let confidence: Double
    let phase: JumpDetectionAlgorithm.JumpPhase
    var jumpCharacteristics: JumpCharacteristics?
}

struct JumpCharacteristics {
    var peakAcceleration: Double = 0
    var airTime: TimeInterval = 0
    var jumpHeight: Double = 0 // in cm
    var quality: JumpQuality = .unknown
}

enum JumpQuality {
    case excellent
    case good
    case fair
    case poor
    case unknown
}

// MARK: - Frequency Analysis Extension

extension JumpDetectionAlgorithm {
    /// Perform FFT to detect jump rhythm
    func detectJumpRhythm(from signal: [Double]) -> Double? {
        guard signal.count >= 64 else { return nil } // Need enough samples for FFT

        // Take last 64 samples (or pad if needed)
        let samples = Array(signal.suffix(64))

        // Convert to float for Accelerate framework
        let floatSamples = samples.map { Float($0) }

        // Perform FFT (simplified - you'd use vDSP for real implementation)
        let frequencies = performFFT(floatSamples)

        // Find dominant frequency (jumps per second)
        guard let maxFreq = frequencies.max() else { return nil }

        return Double(maxFreq * 60) // Convert to jumps per minute
    }

    private func performFFT(_ samples: [Float]) -> [Float] {
        // This is a placeholder - implement actual FFT using Accelerate
        // vDSP_fft_zrip or similar
        samples // Placeholder
    }
}
