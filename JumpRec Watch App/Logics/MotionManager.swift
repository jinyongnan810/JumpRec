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

    var addJump: (Int) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: - Detection Parameters

    private var updateInterval: TimeInterval = 0.01 // 100Hz sampling rate
    private var minTimeBetweenJumps: TimeInterval = 0.30 // Minimum 300ms between jumps
    private var lastJumpTimestamp: TimeInterval = 0

    // MARK: - Detection Algorithm Properties

    private var motionRecording: [String] = []

    // MARK: - Statistics

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

    // MARK: - Private Methods

    private func processMotionData(_ motion: CMDeviceMotion) {
        // Use user acceleration (gravity removed) for better jump detection
        let userAcceleration = motion.userAcceleration
        let userRotaion = motion.rotationRate

        // Process for jump detection
        let isJump = detectJump(motion)

        motionRecording
            .append(
                "\(motion.timestamp),\(userAcceleration.x),\(userAcceleration.y),\(userAcceleration.z),\(userRotaion.x),\(userRotaion.y),\(userRotaion.z),\(isJump)\n"
            )
    }

    private func detectJump(_ motion: CMDeviceMotion) -> Bool {
        // Detect jump using multiple criteria
        // 1. Check minimum time between jumps
        guard motion.timestamp - lastJumpTimestamp > minTimeBetweenJumps else {
            return false
        }
        // 2. Check exceeds threshold
        let result = motion.userAcceleration.y > 0.8 // && motion.rotationRate.x > 4

        if result {
            registerJump(timestamp: motion.timestamp)
        }
        return result
    }

    private func registerJump(timestamp: TimeInterval) {
        lastJumpTimestamp = timestamp
        ConnectivityManager.shared.sendMessage(["watch app": "Detect Jump"])
        addJump(1)
        jumpTimestamps.append(Date())
    }
}
