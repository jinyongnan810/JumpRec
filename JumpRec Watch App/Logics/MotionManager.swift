//
//  MotionManager.swift
//  JumpRec
//
//  Created by kinn on 2025/09/14.
//

import CoreMotion
import Foundation
import Synchronization

/// Manages motion detection and jump counting using device sensors
class MotionManager: NSObject {
    /// Holds lock-protected motion detection state shared between the main actor and sensor queue.
    private final nonisolated class SampleProcessor: Sendable {
        private struct State {
            var isTracking = false
            var trackingStartDate: Date?
            var trackingStartTimestamp: TimeInterval?
            let jumpDetector = JumpDetector(profile: .watch)
            #if DEBUG
                var recordedSamples: [MotionSample] = []
            #endif
        }

        private let state = Mutex(State())

        var isTracking: Bool {
            state.withLock { $0.isTracking }
        }

        func prepareIfNotTracking(thresholdAdjustmentPercentage: Double) {
            state.withLock { state in
                guard !state.isTracking else { return }
                state.jumpDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
                Self.resetDetectionState(&state)
            }
        }

        func startTracking(startDate: Date, thresholdAdjustmentPercentage: Double) {
            state.withLock { state in
                state.jumpDetector.updateThresholdAdjustmentPercentage(thresholdAdjustmentPercentage)
                Self.resetDetectionState(&state)
                state.trackingStartDate = startDate
                state.isTracking = true
            }
        }

        func resetIfNotTracking() {
            state.withLock { state in
                guard !state.isTracking else { return }
                Self.resetDetectionState(&state)
            }
        }

        func updateThresholdAdjustmentPercentage(_ percentage: Double) {
            state.withLock { state in
                state.jumpDetector.updateThresholdAdjustmentPercentage(percentage)
            }
        }

        func stopTracking() {
            state.withLock { state in
                state.isTracking = false
            }
        }

        func reset() {
            state.withLock { state in
                Self.resetDetectionState(&state)
            }
        }

        /// Evaluates one motion sample and returns its session-relative hardware offset if a jump is detected.
        func processSample(_ sample: MotionSample) -> TimeInterval? {
            state.withLock { state in
                guard state.isTracking else { return nil }
                #if DEBUG
                    state.recordedSamples.append(sample)
                #endif
                // Anchor sensor timestamps to session start on the first tracked sample so jump deltas avoid MainActor jitter.
                if state.trackingStartTimestamp == nil {
                    let elapsedAtFirstSample = state.trackingStartDate.map { max(0, Date().timeIntervalSince($0)) } ?? 0
                    state.trackingStartTimestamp = sample.timestamp - elapsedAtFirstSample
                }
                guard state.jumpDetector.processMotionSample(sample) else { return nil }
                guard let trackingStartTimestamp = state.trackingStartTimestamp else { return 0 }
                return max(0, sample.timestamp - trackingStartTimestamp)
            }
        }

        #if DEBUG
            func consumeRecordedSamples() -> [MotionSample] {
                state.withLock { state in
                    let samples = state.recordedSamples
                    state.recordedSamples.removeAll(keepingCapacity: false)
                    return samples
                }
            }
        #endif

        private static func resetDetectionState(_ state: inout State) {
            #if DEBUG
                state.recordedSamples.removeAll(keepingCapacity: true)
            #endif
            state.trackingStartDate = nil
            state.trackingStartTimestamp = nil
            state.jumpDetector.reset()
        }
    }

    // MARK: - Published Properties

    /// Indicates whether motion tracking is currently active.
    var isTracking: Bool {
        sampleProcessor.isTracking
    }

    /// Stores the local jump count used by the watch detector.
    var jumpCount = 0

    /// Delivers accepted jumps and their hardware-derived session offsets back to app state.
    var addJump: @Sendable (Int, TimeInterval) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: - HealthKit

    /// Provides HealthKit workout and mirroring integration.
    private let workoutManager: WorkoutManager

    // MARK: - Detection

    /// Watch sample interval captures brief acceleration impacts.
    private var updateInterval: TimeInterval = 0.01 // 100Hz sampling rate when supported
    /// Synchronizes tracking state, jump detection, and debug samples across actors and the motion queue.
    private let sampleProcessor = SampleProcessor()

    // MARK: - Initialization

    /// Configures the watch motion manager and workout callbacks.
    init(
        addJump: @escaping @Sendable (Int, TimeInterval) -> Void,
        updateHeartRate: @escaping (Int) -> Void,
        updateEnergyBurned: @escaping (Double) -> Void
    ) {
        self.addJump = addJump
        workoutManager = WorkoutManager(updateHeartRate: updateHeartRate, updateEnergyBurned: updateEnergyBurned)
        super.init()
        setupMotionManager()
    }

    /// Sets up Core Motion update intervals and processing queue configuration.
    private func setupMotionManager() {
        // Sample fused motion at 100 Hz without magnetometer calibration prompts.
        motionManager.deviceMotionUpdateInterval = updateInterval

        // Set up operation queue
        queue.maxConcurrentOperationCount = 1
        queue.name = "MotionManagerQueue"
    }

    // MARK: - Public Methods

    /// Warms up Core Motion and prepares the HealthKit workout session during the countdown.
    func prepareForWorkout(
        thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage
    ) {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        workoutManager.prepareWorkout()
        sampleProcessor.prepareIfNotTracking(thresholdAdjustmentPercentage: thresholdAdjustmentPercentage)
        startDeviceMotionStreamIfNeeded()
    }

    /// Starts Watch motion tracking with a relative sensitivity adjustment.
    func startTracking(
        startDate: Date,
        goalType: GoalType,
        goalValue: Int,
        thresholdAdjustmentPercentage: Double = DefaultJumpDetectorThresholdAdjustmentPercentage
    ) {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }

        workoutManager.startWorkout(startDate: startDate, goalType: goalType, goalValue: goalValue)
        sampleProcessor.startTracking(
            startDate: startDate,
            thresholdAdjustmentPercentage: thresholdAdjustmentPercentage
        )
        startDeviceMotionStreamIfNeeded()
    }

    /// Stops pre-warmed motion updates and ends the prepared HealthKit session when cancelled before start.
    func cancelPreparation() {
        motionManager.stopDeviceMotionUpdates()
        sampleProcessor.resetIfNotTracking()
        workoutManager.cancelPreparedWorkout()
    }

    /// Changes sensitivity without clearing jump counts, CSV samples, or refractory timing.
    func updateThresholdAdjustmentPercentage(_ percentage: Double) {
        sampleProcessor.updateThresholdAdjustmentPercentage(percentage)
    }

    /// Stop motion tracking
    func stopTracking() {
        motionManager.stopDeviceMotionUpdates()
        sampleProcessor.stopTracking()
        workoutManager.stopWorkout()
    }

    /// Sends jump progress updates to the mirrored workout session.
    func recordJump(jumpCount: Int, jumpOffset: TimeInterval) {
        workoutManager.sendJumpUpdate(jumpCount: jumpCount, jumpOffset: jumpOffset)
    }

    #if DEBUG
        /// Returns and clears recorded motion samples collected during the session.
        func consumeRecordedSamples() -> [MotionSample] {
            sampleProcessor.consumeRecordedSamples()
        }
    #endif

    /// Reset the current session
    func resetSession() {
        jumpCount = 0
        sampleProcessor.reset()
    }

    // MARK: - Private Methods

    /// Starts the 100 Hz Core Motion stream if it is not already running.
    private func startDeviceMotionStreamIfNeeded() {
        guard !motionManager.isDeviceMotionActive else { return }

        let sampleProcessor = sampleProcessor
        let addJump = addJump

        // Forward samples into the detector only after tracking is armed at countdown completion.
        motionManager.startDeviceMotionUpdates(to: queue) { motion, _ in
            guard let motion else { return }
            let sample = MotionSample(
                userAccelerationX: motion.userAcceleration.x,
                userAccelerationY: motion.userAcceleration.y,
                userAccelerationZ: motion.userAcceleration.z,
                rotationRateX: motion.rotationRate.x,
                rotationRateY: motion.rotationRate.y,
                rotationRateZ: motion.rotationRate.z,
                timestamp: motion.timestamp
            )

            // Each accepted sample reports one jump and its hardware timestamp offset to app state.
            if let jumpOffset = sampleProcessor.processSample(sample) {
                addJump(1, jumpOffset)
            }
        }
    }
}
