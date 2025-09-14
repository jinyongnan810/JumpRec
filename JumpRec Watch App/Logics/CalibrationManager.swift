//
//  CalibrationManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import Combine
import CoreMotion
import Foundation
import Observation
import WatchKit

// MARK: - Calibration States

enum CalibrationState: Equatable {
    case idle
    case collectingBaseline // User standing still
    case collectingJumps // User performing test jumps
    case analyzingData // Processing calibration data
    case completed
    case failed(String)
}

/// Manages calibration for personalized jump detection
@Observable
class CalibrationManager {
    // MARK: - Published Properties

    var state: CalibrationState = .idle
    var progress: Double = 0.0
    var instructions: String = ""
    var calibrationProfile: CalibrationProfile?

    // MARK: - Calibration Data

    private var baselineData: [AccelerationSample] = []
    private var jumpData: [AccelerationSample] = []
    private var testJumpCount = 0
    private let requiredTestJumps = 10

    // MARK: - Data Collection

    private var motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private var startTime: Date?

    // MARK: - Analysis Results

    private var baselineNoise: Double = 0
    private var averagePeakAcceleration: Double = 0
    private var averageJumpDuration: Double = 0
    private var jumpSignature: [Double] = []

    // MARK: - Public Methods

    /// Start the calibration process
    func startCalibration() {
        resetCalibration()
        state = .collectingBaseline
        instructions = "Please stand still for 3 seconds..."
        progress = 0.0

        startBaselineCollection()
    }

    /// Cancel ongoing calibration
    func cancelCalibration() {
        stopMotionUpdates()
        resetCalibration()
        state = .idle
    }

    /// Apply calibration profile to motion manager
    func applyProfile(_ profile: CalibrationProfile, to motionManager: MotionManager) {
        motionManager.setSensitivity(profile.optimalThreshold)
        motionManager.setMinTimeBetweenJumps(profile.minJumpInterval)

        if let height = profile.userHeight {
            motionManager.setUserHeight(height)
        }
    }

    // MARK: - Baseline Collection

    private func startBaselineCollection() {
        startTime = Date()
        baselineData.removeAll()

        motionManager.accelerometerUpdateInterval = 0.01
        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }

            collectBaselineData(data)

            // Check if baseline collection is complete (3 seconds)
            if let startTime,
               Date().timeIntervalSince(startTime) >= 3.0
            {
                finishBaselineCollection()
            }
        }
    }

    private func collectBaselineData(_ data: CMAccelerometerData) {
        let sample = AccelerationSample(
            timestamp: data.timestamp,
            x: data.acceleration.x,
            y: data.acceleration.y,
            z: data.acceleration.z
        )
        baselineData.append(sample)

        // Update progress
        if let startTime {
            let elapsed = Date().timeIntervalSince(startTime)
            DispatchQueue.main.async {
                self.progress = min(elapsed / 3.0, 1.0) * 0.3 // 30% for baseline
            }
        }
    }

    private func finishBaselineCollection() {
        stopMotionUpdates()

        // Analyze baseline
        analyzeBaseline()

        // Move to jump collection
        DispatchQueue.main.async {
            self.state = .collectingJumps
            self.instructions = "Now perform \(self.requiredTestJumps) rope jumps at your normal pace"
            self.progress = 0.3
        }

        // Wait 2 seconds before starting jump collection
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.startJumpCollection()
        }
    }

    private func analyzeBaseline() {
        guard !baselineData.isEmpty else { return }

        // Calculate noise floor (standard deviation of baseline)
        let accelerations = baselineData.map { sample in
            sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)
        }

        let mean = accelerations.reduce(0, +) / Double(accelerations.count)
        let variance = accelerations.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerations.count)
        baselineNoise = sqrt(variance)

        print("Baseline noise level: \(baselineNoise)")
    }

    // MARK: - Jump Collection

    private func startJumpCollection() {
        startTime = Date()
        jumpData.removeAll()
        testJumpCount = 0

        motionManager.deviceMotionUpdateInterval = 0.01
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }

            collectJumpData(motion)

            // Check for timeout (30 seconds max)
            if let startTime,
               Date().timeIntervalSince(startTime) >= 30.0
            {
                finishJumpCollection()
            }
        }
    }

    private func collectJumpData(_ motion: CMDeviceMotion) {
        let userAccel = motion.userAcceleration
        let sample = AccelerationSample(
            timestamp: motion.timestamp,
            x: userAccel.x,
            y: userAccel.y,
            z: userAccel.z
        )
        jumpData.append(sample)

        // Detect jumps in real-time for counting
        if detectTestJump(sample) {
            testJumpCount += 1

            DispatchQueue.main.async {
                self.progress = 0.3 + (Double(self.testJumpCount) / Double(self.requiredTestJumps)) * 0.5
                self.instructions = "Jump \(self.testJumpCount) of \(self.requiredTestJumps) detected"
            }

            // Provide haptic feedback
            provideCalibrationFeedback()

            // Check if we have enough jumps
            if testJumpCount >= requiredTestJumps {
                finishJumpCollection()
            }
        }
    }

    private func detectTestJump(_ sample: AccelerationSample) -> Bool {
        // Simple threshold detection for calibration
        let totalAccel = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)

        // Use a conservative threshold during calibration
        if totalAccel > 1.3, sample.timestamp - lastJumpTime > 0.3 {
            lastJumpTime = sample.timestamp
            return true
        }
        return false
    }

    private var lastJumpTime: TimeInterval = 0

    private func finishJumpCollection() {
        stopMotionUpdates()

        DispatchQueue.main.async {
            self.state = .analyzingData
            self.instructions = "Analyzing your jump pattern..."
            self.progress = 0.8
        }

        // Perform analysis
        analyzeJumpData()
    }

    // MARK: - Data Analysis

    private func analyzeJumpData() {
        guard !jumpData.isEmpty else {
            DispatchQueue.main.async {
                self.state = .failed("No jump data collected")
            }
            return
        }

        // Extract jump characteristics
        let peaks = findPeaks(in: jumpData)

        guard peaks.count >= requiredTestJumps else {
            DispatchQueue.main.async {
                self.state = .failed("Not enough jumps detected. Please try again.")
            }
            return
        }

        // Calculate statistics
        calculateJumpStatistics(from: peaks)

        // Create calibration profile
        createCalibrationProfile()

        DispatchQueue.main.async {
            self.state = .completed
            self.instructions = "Calibration complete!"
            self.progress = 1.0
        }
    }

    private func findPeaks(in samples: [AccelerationSample]) -> [JumpPeak] {
        var peaks: [JumpPeak] = []
        let windowSize = 50 // 0.5 seconds at 100Hz

        for i in windowSize ..< (samples.count - windowSize) {
            let window = Array(samples[(i - windowSize / 2) ... (i + windowSize / 2)])
            let accelerations = window.map { s in
                sqrt(s.x * s.x + s.y * s.y + s.z * s.z)
            }

            if let maxAccel = accelerations.max(),
               let maxIndex = accelerations.firstIndex(of: maxAccel),
               maxIndex == windowSize / 2
            { // Peak is in center of window
                // This is a local maximum
                if maxAccel > 1.3 + baselineNoise * 3 { // 3 sigma above noise
                    peaks.append(JumpPeak(
                        timestamp: samples[i].timestamp,
                        acceleration: maxAccel,
                        verticalComponent: samples[i].y
                    ))
                }
            }
        }

        // Filter peaks too close together
        return filterNearbyPeaks(peaks)
    }

    private func filterNearbyPeaks(_ peaks: [JumpPeak]) -> [JumpPeak] {
        guard !peaks.isEmpty else { return [] }

        var filtered: [JumpPeak] = []
        var lastTimestamp: TimeInterval = 0

        for peak in peaks.sorted(by: { $0.timestamp < $1.timestamp }) {
            if peak.timestamp - lastTimestamp > 0.3 {
                filtered.append(peak)
                lastTimestamp = peak.timestamp
            }
        }

        return filtered
    }

    private func calculateJumpStatistics(from peaks: [JumpPeak]) {
        // Average peak acceleration
        averagePeakAcceleration = peaks.map(\.acceleration).reduce(0, +) / Double(peaks.count)

        // Jump intervals
        var intervals: [TimeInterval] = []
        for i in 1 ..< peaks.count {
            intervals.append(peaks[i].timestamp - peaks[i - 1].timestamp)
        }

        if !intervals.isEmpty {
            averageJumpDuration = intervals.reduce(0, +) / Double(intervals.count)
        }

        // Create jump signature (normalized pattern)
        jumpSignature = createJumpSignature(from: peaks)
    }

    private func createJumpSignature(from peaks: [JumpPeak]) -> [Double] {
        // Create a normalized pattern representing the user's jump style
        guard let firstPeak = peaks.first else { return [] }

        var signature: [Double] = []

        // Find data around first peak
        if let peakIndex = jumpData.firstIndex(where: { abs($0.timestamp - firstPeak.timestamp) < 0.01 }) {
            let start = max(0, peakIndex - 25)
            let end = min(jumpData.count, peakIndex + 25)

            for i in start ..< end {
                let sample = jumpData[i]
                let accel = sqrt(sample.x * sample.x + sample.y * sample.y + sample.z * sample.z)
                signature.append(accel)
            }

            // Normalize
            if let maxVal = signature.max(), maxVal > 0 {
                signature = signature.map { $0 / maxVal }
            }
        }

        return signature
    }

    // MARK: - Profile Creation

    private func createCalibrationProfile() {
        let profile = CalibrationProfile(
            id: UUID(),
            createdAt: Date(),
            baselineNoise: baselineNoise,
            averagePeakAcceleration: averagePeakAcceleration,
            optimalThreshold: calculateOptimalThreshold(),
            minJumpInterval: max(0.2, averageJumpDuration * 0.7),
            maxJumpInterval: min(2.0, averageJumpDuration * 1.5),
            jumpSignature: jumpSignature,
            confidenceLevel: calculateConfidence()
        )

        DispatchQueue.main.async {
            self.calibrationProfile = profile
        }

        // Save profile
        saveProfile(profile)
    }

    private func calculateOptimalThreshold() -> Double {
        // Set threshold between baseline noise and average peak
        let margin = (averagePeakAcceleration - baselineNoise) * 0.3
        return baselineNoise + margin
    }

    private func calculateConfidence() -> Double {
        // Confidence based on consistency of jumps
        let peaks = findPeaks(in: jumpData)
        guard peaks.count > 1 else { return 0.5 }

        // Calculate standard deviation of peak accelerations
        let accelerations = peaks.map(\.acceleration)
        let mean = accelerations.reduce(0, +) / Double(accelerations.count)
        let variance = accelerations.map { pow($0 - mean, 2) }.reduce(0, +) / Double(accelerations.count)
        let stdDev = sqrt(variance)

        // Lower std dev = higher confidence
        let cv = stdDev / mean // Coefficient of variation

        if cv < 0.1 { return 0.95 }
        if cv < 0.2 { return 0.85 }
        if cv < 0.3 { return 0.75 }
        return 0.65
    }

    // MARK: - Persistence

    private func saveProfile(_ profile: CalibrationProfile) {
        if let encoded = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(encoded, forKey: "CalibrationProfile")
        }
    }

    static func loadProfile() -> CalibrationProfile? {
        guard let data = UserDefaults.standard.data(forKey: "CalibrationProfile"),
              let profile = try? JSONDecoder().decode(CalibrationProfile.self, from: data)
        else {
            return nil
        }
        return profile
    }

    // MARK: - Helper Methods

    private func stopMotionUpdates() {
        motionManager.stopAccelerometerUpdates()
        motionManager.stopDeviceMotionUpdates()
    }

    private func resetCalibration() {
        baselineData.removeAll()
        jumpData.removeAll()
        testJumpCount = 0
        progress = 0
        instructions = ""
    }

    private func provideCalibrationFeedback() {
        #if os(watchOS)
            WKInterfaceDevice.current().play(.click)
        #endif
    }
}

// MARK: - Supporting Types

struct AccelerationSample {
    let timestamp: TimeInterval
    let x: Double
    let y: Double
    let z: Double
}

struct JumpPeak {
    let timestamp: TimeInterval
    let acceleration: Double
    let verticalComponent: Double
}

struct CalibrationProfile: Codable {
    let id: UUID
    let createdAt: Date

    // Baseline characteristics
    let baselineNoise: Double

    // Jump characteristics
    let averagePeakAcceleration: Double
    let optimalThreshold: Double
    let minJumpInterval: TimeInterval
    let maxJumpInterval: TimeInterval
    let jumpSignature: [Double]

    // Meta
    let confidenceLevel: Double
    var userHeight: Double?
    var userWeight: Double?

    var description: String {
        """
        Calibration Profile:
        - Threshold: \(String(format: "%.2f", optimalThreshold))g
        - Avg Peak: \(String(format: "%.2f", averagePeakAcceleration))g
        - Jump Interval: \(String(format: "%.2f", minJumpInterval))-\(String(format: "%.2f", maxJumpInterval))s
        - Confidence: \(String(format: "%.0f", confidenceLevel * 100))%
        """
    }
}
