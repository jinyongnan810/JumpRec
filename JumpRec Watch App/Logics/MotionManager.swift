//
//  MotionManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import CoreMotion
import Foundation

let csvHeader = "Timestamp,AX,AY,AZ,RX,RY,RZ,Jump\n"

/// Manages motion detection and jump counting using device sensors
class MotionManager: NSObject {
    // MARK: - Published Properties

    /// Indicates whether motion tracking is currently active.
    var isTracking = false
    /// Stores the local jump count used by the watch detector.
    var jumpCount = 0

    /// Delivers accepted jumps back to app state.
    var addJump: @MainActor (Int) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: - HealthKit

    /// Provides HealthKit workout and mirroring integration.
    private let workoutManager: WorkoutManager

    // MARK: - Detection

    // The watch runs at a higher sample rate than the phone path because impact-style jump signals are brief.
    /// Defines the motion sample interval used by the watch detector.
    private var updateInterval: TimeInterval = 0.025 // 40Hz sampling rate when supported
    /// Shared jump detector configured for watch motion data.
    private let jumpDetector = JumpDetector(profile: .watch)

    /// Stores CSV rows when motion recording is enabled.
    private var motionRecording: [String] = []

    // MARK: - Initialization

    /// Configures the watch motion manager and workout callbacks.
    init(
        addJump: @escaping @MainActor (Int) -> Void,
        updateHeartRate: @escaping @MainActor (Int) -> Void,
        updateEnergyBurned: @escaping @MainActor (Double) -> Void
    ) {
        self.addJump = addJump
        workoutManager = WorkoutManager(updateHeartRate: updateHeartRate, updateEnergyBurned: updateEnergyBurned)
        super.init()
        setupMotionManager()
    }

    /// Sets up Core Motion update intervals and processing queue configuration.
    private func setupMotionManager() {
        // Device motion provides both acceleration and gyro data in one stream, which is the only input
        // the shared detector needs once it is converted into `MotionSample`.
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
    func startTracking(startDate: Date, goalType: GoalType, goalValue: Int) {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        workoutManager.startWorkout(startDate: startDate, goalType: goalType, goalValue: goalValue)

        resetSession()
        isTracking = true
        motionRecording = [csvHeader]

        // The watch forwards every sample into the shared detector and only owns workout/session plumbing.
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

    /// Sends jump progress updates to the mirrored workout session.
    func recordJump(jumpCount: Int, jumpOffset: TimeInterval) {
        workoutManager.sendJumpUpdate(jumpCount: jumpCount, jumpOffset: jumpOffset)
    }

    /// Sends the recorded motion CSV to the iPhone companion app.
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

    /// Converts raw device motion into normalized samples for the jump detector.
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

        // The detector returns a boolean event instead of a score so the watch UI can stay simple and update live.
        if jumpDetector.processMotionSample(sample) {
            Task { @MainActor [addJump] in
                addJump(1)
            }
        }
    }
}
