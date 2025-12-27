//
//  MotionManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/14.
//

import Combine
import CoreMotion
import Foundation
import HealthKit
import WatchKit

let csvHeader = "Timestamp,AX,AY,AZ,RX,RY,RZ,Jump\n"

/// Manages motion detection and jump counting using device sensors
class MotionManager: NSObject {
    // MARK: - Published Properties

    var isTracking = false
    var jumpCount = 0

    var addJump: (Int) -> Void
    var updateHeartRate: (Int) -> Void
    var updateEnergyBurned: (Double) -> Void

    // MARK: - Motion Components

    private let motionManager = CMMotionManager()
    private let queue = OperationQueue()

    // MARK: - HealthKit Related

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var energyBurnedQuery: HKAnchoredObjectQuery?

    // MARK: - Detection Parameters

    private var updateInterval: TimeInterval = 0.05 // 20Hz sampling rate
    private var minTimeBetweenJumps: TimeInterval = 0.30 // Minimum 300ms between jumps
    private var lastJumpTimestamp: TimeInterval = 0

    // MARK: - Detection Algorithm Properties

    private var motionRecording: [String] = []

    // MARK: - Statistics

    private var jumpTimestamps: [Date] = []

    // MARK: - Initialization

    init(addJump: @escaping (Int) -> Void, updateHeartRate: @escaping (Int) -> Void, updateEnergyBurned: @escaping (Double) -> Void) {
        self.addJump = addJump
        self.updateHeartRate = updateHeartRate
        self.updateEnergyBurned = updateEnergyBurned
        super.init()
        requestHealthKitAuthorization()
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

    /// Request permission for collecting health data
    func requestHealthKitAuthorization() {
        let typesToShare: Set = [
            HKQuantityType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]

        let typesToRead: Set = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            print("request health permission: \(success)")
            if let error {
                print("permission request error: \(error)")
            }
        }
    }

    // MARK: - Public Methods

    /// Start motion tracking and jump detection
    func startTracking() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }
        // healthkit related
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            // Set up session delegate
            session?.delegate = self
            builder?.delegate = self

            // Start the workout
            let startDate = Date()
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { success, error in
                print("Collecting health data started: \(success)")
                if let error {
                    print("Failed to start collecting health data: \(error)")
                }

                let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
                let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
                self.heartRateQuery = HKAnchoredObjectQuery(
                    type: heartRateType,
                    predicate: predicate,
                    anchor: nil,
                    limit: HKObjectQueryNoLimit
                ) { _, _, _, _, _ in
                }

                let energyBurnedType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
                let energyBurnedPredicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
                self.energyBurnedQuery = HKAnchoredObjectQuery(
                    type: energyBurnedType,
                    predicate: energyBurnedPredicate,
                    anchor: nil,
                    limit: HKObjectQueryNoLimit
                ) { _, _, _, _, _ in
                }

                // Set updateHandler for live delivery
                self.heartRateQuery?.updateHandler = { _, samples, _, _, _ in
                    if let samples = samples as? [HKQuantitySample] {
                        for sample in samples {
                            let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                            print("heartrate: \(bpm) bpm")
                            self.updateHeartRate(Int(bpm))
                        }
                    }
                }
                if let heartRateQuery = self.heartRateQuery {
                    self.healthStore.execute(heartRateQuery)
                }
                self.energyBurnedQuery?.updateHandler = { _, samples, _, _, _ in
                    if let samples = samples as? [HKQuantitySample] {
                        for sample in samples {
                            let kcal = sample.quantity.doubleValue(for: HKUnit.kilocalorie())
//                            print("eneryBurned: \(kcal)")
                            self.updateEnergyBurned(kcal)
                        }
                    }
                }
                if let energyBurnedQuery = self.energyBurnedQuery {
                    self.healthStore.execute(energyBurnedQuery)
                }
            }
        } catch {
            print("Collecting health data failed")
            return
        }

        // motion related
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
        // motion related
        motionManager.stopDeviceMotionUpdates()
        motionManager.stopAccelerometerUpdates()
        // healthkit related
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
        }
        if let energyBurnedQuery {
            healthStore.stop(energyBurnedQuery)
        }
        session?.end()
        builder?.endCollection(withEnd: Date()) {
            _,
                _ in
            self.builder?.finishWorkout {
                workout,
                    _ in
                print("workout finished: \(String(describing: workout))")
            }
        }

        // upload collected data
        // TODO: upload only on debug mode
//        saveCSVtoICloud()
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
//        let userAcceleration = motion.userAcceleration
//        let userRotaion = motion.rotationRate

        // Process for jump detection
        let _ = detectJump(motion)

//        motionRecording
//            .append(
//                "\(motion.timestamp),\(userAcceleration.x),\(userAcceleration.y),\(userAcceleration.z),\(userRotaion.x),\(userRotaion.y),\(userRotaion.z),\(isJump)\n"
//            )
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
//        ConnectivityManager.shared.sendMessage(["watch app": "Detect Jump"])
        addJump(1)
//        jumpTimestamps.append(Date())
    }
}

// MARK: - HKWorkoutSessionDelegate

extension MotionManager: HKWorkoutSessionDelegate {
    func workoutSession(_: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from _: HKWorkoutSessionState,
                        date _: Date)
    {
        // Handle state changes
        switch toState {
        case .running:
            print("Workout started")
        case .ended:
            print("Workout ended")
        default:
            break
        }
    }

    func workoutSession(_: HKWorkoutSession,
                        didFailWithError error: Error)
    {
        print("workout session error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension MotionManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>)
    {
        print("1: collected health data types: \(collectedTypes)")
//        let statistics = workoutBuilder.statistics(for: .quantityType(forIdentifier: .heartRate)!)
//        let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
//        if let value = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
//            print("1: Live Heart Rate: \(value) BPM")
//            updateHeartRate(Int(value))
//        } else {
//            print("1: No heart rate available")
//        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        print("2: collected health data: \(workoutBuilder)")
//        let statistics = workoutBuilder.statistics(for: .quantityType(forIdentifier: .heartRate)!)
//        let heartRateUnit = HKUnit.count().unitDivided(by: HKUnit.minute())
//        if let value = statistics?.mostRecentQuantity()?.doubleValue(for: heartRateUnit) {
//            print("2: Live Heart Rate: \(value) BPM")
//            updateHeartRate(Int(value))
//        } else {
//            print("2: No heart rate available")
//        }
    }
}
