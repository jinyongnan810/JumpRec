//
//  MotionManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import CoreMotion
import Foundation
import JumpRecShared

let csvHeader = "Timestamp,AX,AY,AZ,RX,RY,RZ,Jump\n"

/// Manages motion detection and jump counting using device sensors
class MotionManager: NSObject {
    // MARK: - Published Properties

    var isTracking = false
    var jumpCount = 0

    var addJump: (Int) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: - HealthKit

    private let workoutManager: WorkoutManager

    // MARK: - Detection

    private var updateInterval: TimeInterval = 0.05 // 20Hz sampling rate
    private let jumpDetector = JumpDetector()

    private var motionRecording: [String] = []

    // MARK: - Initialization

    init(addJump: @escaping (Int) -> Void, updateHeartRate: @escaping (Int) -> Void, updateEnergyBurned: @escaping (Double) -> Void) {
        self.addJump = addJump
        workoutManager = WorkoutManager(updateHeartRate: updateHeartRate, updateEnergyBurned: updateEnergyBurned)
        super.init()
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

        workoutManager.startWorkout()

        resetSession()
        isTracking = true
        motionRecording = [csvHeader]

        // Start device motion updates for more accurate data
        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            guard let self, let motion else { return }
            processMotionData(motion)
        }
    }

    /// Stop motion tracking
    func stopTracking() {
        isTracking = false
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        workoutManager.stopWorkout()
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
        motionRecording.removeAll()
        jumpDetector.reset()
    }

    // MARK: - Private Methods

    private func processMotionData(_ motion: CMDeviceMotion) {
        let sample = MotionSample(
            userAccelerationX: motion.userAcceleration.x,
            userAccelerationY: motion.userAcceleration.y,
            userAccelerationZ: motion.userAcceleration.z,
            rotationRateX: motion.rotationRate.x,
            rotationRateY: motion.rotationRate.y,
            rotationRateZ: motion.rotationRate.z,
            timestamp: motion.timestamp
        )

        if jumpDetector.processMotionSample(sample) {
            addJump(1)
        }
    }
}
