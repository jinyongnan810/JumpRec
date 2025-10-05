//
//  MotionManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import Combine
import CoreMotion
import Foundation
import WatchKit

let csvHeader = "Timestamp,AX,AY,AZ,RX,RY,RZ,Jump\n"

/// Manages motion detection and jump counting using device sensors
class MotionManager {
    // MARK: - Published Properties

    var isTracking = false
    var jumpCount = 0
    var currentAcceleration: Double = 0
    var detectionSensitivity: Double = 1.0 // G-force threshold
    var isCalibrating = false

    var addJump: (Int) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()
    private let jumpDetectionAlgorithm = JumpDetectionAlgorithm()

    // MARK: - Detection Parameters

    private var updateInterval: TimeInterval = 0.01 // 100Hz sampling rate
    private var minTimeBetweenJumps: TimeInterval = 0.3 // Minimum 300ms between jumps
    private var lastJumpTimestamp: TimeInterval = 0

    // MARK: - Detection Algorithm Properties

    private var motionRecording: [String] = []

    // MARK: - Calibration Properties

    private var calibrationData: [Double] = []
    private var noiseFloor: Double = 0.1 // Baseline noise level
    private var userHeight: Double = 170 // cm, affects expected acceleration

    // MARK: - Statistics

    private var sessionStartTime: Date?
    private var jumpTimestamps: [Date] = []

    // MARK: - Initialization

    init(addJump: @escaping (Int) -> Void) {
        self.addJump = addJump
        setupMotionManager()
    }

    private func setupMotionManager() {
        // Configure motion manager
        motionManager.deviceMotionUpdateInterval = updateInterval
        motionManager.accelerometerUpdateInterval = updateInterval

        // Enable background motion updates
        motionManager.showsDeviceMovementDisplay = true

        // Set up operation queue
        queue.maxConcurrentOperationCount = 1
        queue.name = "MotionManagerQueue"
    }

    // MARK: - Public Methods

    /// Start motion tracking and jump detection
    func startTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        resetSession()
        isTracking = true
        sessionStartTime = Date()
        motionRecording = [csvHeader]

        // Start device motion updates for more accurate data
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            processMotionData(motion)
        }

        // Also start raw accelerometer as backup
//        motionManager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
//            guard let self, let data else { return }
//            processAccelerometerData(data)
//        }
    }

    /// Stop motion tracking
    func stopTracking() {
        isTracking = false
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        saveCSVtoICloud()
        motionRecording.removeAll()

        // Calculate session statistics
        if let startTime = sessionStartTime {
            let duration = Date().timeIntervalSince(startTime)
            print("Session ended: \(jumpCount) jumps in \(duration) seconds")
            print("Jump timestamps: \(jumpTimestamps)")
        }
    }

    func saveCSVtoICloud(filename _: String = "motion.csv") {
        let csvText = motionRecording.joined()
        ConnectivityManager.shared
            .sendCSV(csvText, filename: "motion_\(Date().timeIntervalSince1970).csv")
    }

    /// Reset the current session
    func resetSession() {
        jumpCount = 0
        jumpTimestamps.removeAll()
        motionRecording.removeAll()
        lastJumpTimestamp = 0
    }

    /// Start calibration mode
    func startCalibration() {
        isCalibrating = true
        calibrationData.removeAll()
        motionRecording.removeAll()

        // Collect baseline data for 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.finishCalibration()
        }
    }

    // MARK: - Private Methods

    private func processMotionData(_ motion: CMDeviceMotion) {
        // Use user acceleration (gravity removed) for better jump detection
        let userAcceleration = motion.userAcceleration
        let userRotaion = motion.rotationRate

        // Calculate total acceleration magnitude
        let totalAcceleration = sqrt(
            userAcceleration.x * userAcceleration.x +
                userAcceleration.y * userAcceleration.y +
                userAcceleration.z * userAcceleration.z
        )

        // Update on main thread for UI
//        DispatchQueue.main.async { [weak self] in
//            self?.currentAcceleration = totalAcceleration
//        }

        // Process for jump detection
        let isJump = detectJump(acceleration: totalAcceleration,
                                verticalAcceleration: userAcceleration.y,
                                timestamp: motion.timestamp)

        motionRecording
            .append(
                "\(motion.timestamp),\(userAcceleration.x),\(userAcceleration.y),\(userAcceleration.z),\(userRotaion.x),\(userRotaion.y),\(userRotaion.z),\(isJump)\n"
            )

        // Collect calibration data if needed
        if isCalibrating {
            calibrationData.append(totalAcceleration)
        }
    }

    private func processAccelerometerData(_ data: CMAccelerometerData) {
        // Only use if device motion is not available
        if motionManager.isDeviceMotionActive {
            return
        }
        // Fallback processing if device motion fails
        // This includes gravity, so we need different thresholds
        let acceleration = data.acceleration
        let totalAcceleration = sqrt(
            acceleration.x * acceleration.x +
                acceleration.y * acceleration.y +
                acceleration.z * acceleration.z
        )
        detectJumpFromRawAccelerometer(
            acceleration: totalAcceleration - 1.0, // Subtract gravity
            timestamp: data.timestamp
        )
    }

    private func detectJump(acceleration _: Double,
                            verticalAcceleration: Double,
                            timestamp: TimeInterval) -> Bool
    {
        // Detect jump using multiple criteria
        let result = isJumpDetected(verticalAcceleration: verticalAcceleration, timestamp: timestamp)
        if result {
            registerJump(timestamp: timestamp)
        }
        return result
    }

    private func isJumpDetected(verticalAcceleration: Double,
                                timestamp: TimeInterval) -> Bool
    {
        // 1. Check minimum time between jumps
        guard timestamp - lastJumpTimestamp > minTimeBetweenJumps else {
            return false
        }

        // 2. Check exceeds threshold
        let adjustedThreshold = detectionSensitivity - noiseFloor
        guard verticalAcceleration > adjustedThreshold else { return false }
        return true
    }

    private func detectJumpFromRawAccelerometer(acceleration: Double,
                                                timestamp: TimeInterval)
    {
        // Simplified detection for raw accelerometer
        // Uses different thresholds since gravity is included
        guard timestamp - lastJumpTimestamp > minTimeBetweenJumps else { return }

        print("Detect jump in raw accelerometer")

        if acceleration > detectionSensitivity {
            registerJump(timestamp: timestamp)
        }
    }

    private func registerJump(timestamp: TimeInterval) {
        lastJumpTimestamp = timestamp
        addJump(1)
        jumpTimestamps.append(Date())
    }

    private func finishCalibration() {
        guard !calibrationData.isEmpty else {
            isCalibrating = false
            return
        }

        // Calculate noise floor from calibration data
        let sortedData = calibrationData.sorted()

        // Use 95th percentile as noise ceiling
        let percentileIndex = Int(Double(sortedData.count) * 0.95)
        noiseFloor = sortedData[percentileIndex]

        // Adjust sensitivity based on noise
        if noiseFloor > 0.2 {
            // High noise environment, increase threshold
            detectionSensitivity = max(1.8, detectionSensitivity)
        }

        print("Calibration complete. Noise floor: \(noiseFloor)")
        isCalibrating = false
    }

    // MARK: - Configuration Methods

    /// Adjust detection sensitivity (1.0 - 3.0 G)
    func setSensitivity(_ sensitivity: Double) {
        detectionSensitivity = max(1.0, min(3.0, sensitivity))
    }

    /// Set minimum time between jumps (prevents double counting)
    func setMinTimeBetweenJumps(_ time: TimeInterval) {
        minTimeBetweenJumps = max(0.2, min(1.0, time))
    }

    /// Set user height for better detection (affects expected patterns)
    func setUserHeight(_ height: Double) {
        userHeight = height
        // Adjust thresholds based on height
        // Taller people typically have higher peak accelerations
        let heightFactor = height / 170.0 // Normalized to average height
        detectionSensitivity = detectionSensitivity * (0.9 + (heightFactor * 0.1))
    }

    // MARK: - Statistics Methods

    /// Get current jump rate (jumps per minute)
    func getCurrentJumpRate() -> Double {
        guard jumpTimestamps.count >= 2 else { return 0 }

        let recentJumps = jumpTimestamps.suffix(10)
        guard let first = recentJumps.first,
              let last = recentJumps.last else { return 0 }

        let timeInterval = last.timeIntervalSince(first)
        guard timeInterval > 0 else { return 0 }

        return Double(recentJumps.count - 1) / timeInterval * 60
    }

    /// Get average time between jumps
    func getAverageJumpInterval() -> TimeInterval {
        guard jumpTimestamps.count >= 2 else { return 0 }

        var intervals: [TimeInterval] = []
        for i in 1 ..< jumpTimestamps.count {
            intervals.append(jumpTimestamps[i].timeIntervalSince(jumpTimestamps[i - 1]))
        }

        return intervals.reduce(0, +) / Double(intervals.count)
    }
}

// MARK: - Motion State

enum MotionState {
    case idle
    case preparingJump // Downward motion before jump
    case ascending // Going up
    case peak // At the top
    case descending // Coming down
    case landing // Impact
}

// MARK: - Jump Detection Configuration

struct JumpDetectionConfig {
    var sensitivity: Double = 1.5
    var minTimeBetweenJumps: TimeInterval = 0.3
    var useAdvancedFiltering: Bool = true
    var enableHapticFeedback: Bool = true
    var noiseReduction: Bool = true
}
