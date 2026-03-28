//
//  WorkoutManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/03/01.
//

import Foundation
import HealthKit

/// Manages HealthKit workout sessions, heart rate, and energy burned tracking.
class WorkoutManager: NSObject {
    // MARK: - Callbacks

    /// Delivers heart-rate updates back to app state.
    var updateHeartRate: (Int) -> Void
    /// Delivers energy-burned updates back to app state.
    var updateEnergyBurned: (Double) -> Void

    // MARK: - HealthKit State

    /// Provides HealthKit authorization and workout access.
    private let healthStore = HKHealthStore()
    /// Tracks the active HealthKit workout session.
    private var session: HKWorkoutSession?
    /// Tracks the active live workout builder.
    private var builder: HKLiveWorkoutBuilder?
    /// Streams live heart-rate samples during the workout.
    private var heartRateQuery: HKAnchoredObjectQuery?
    /// Streams active-energy samples during the workout.
    private var energyBurnedQuery: HKAnchoredObjectQuery?
    /// Encodes mirrored payloads sent to the iPhone app.
    private let encoder = JSONEncoder()
    /// Stores the current average heart rate for mirrored updates.
    private var averageHeartRate: Int?
    /// Stores the current peak heart rate for mirrored updates.
    private var peakHeartRate: Int?
    /// Accumulates heart-rate values for averaging.
    private var heartRateSum = 0
    /// Counts heart-rate samples for averaging.
    private var heartRateSamples = 0

    // MARK: - Initialization

    /// Requests authorization and stores callbacks for workout metrics.
    init(updateHeartRate: @escaping (Int) -> Void, updateEnergyBurned: @escaping (Double) -> Void) {
        self.updateHeartRate = updateHeartRate
        self.updateEnergyBurned = updateEnergyBurned
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization

    /// Requests the HealthKit permissions required by the watch workout.
    func requestAuthorization() {
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

    // MARK: - Workout Session

    /// Starts a jump-rope workout and begins mirroring it to the iPhone app.
    func startWorkout(startDate: Date, goalType: GoalType, goalValue: Int) {
        averageHeartRate = nil
        peakHeartRate = nil
        heartRateSum = 0
        heartRateSamples = 0
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { success, error in
                print("Collecting health data started: \(success)")
                if let error {
                    print("Failed to start collecting health data: \(error)")
                }

                self.startMirroring(startDate: startDate, goalType: goalType, goalValue: goalValue)
                self.startHeartRateQuery()
                self.startEnergyBurnedQuery()
            }
        } catch {
            print("Collecting health data failed")
        }
    }

    /// Ends the workout, sends final mirrored metrics, and saves it to HealthKit.
    func stopWorkout() {
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
        }
        if let energyBurnedQuery {
            healthStore.stop(energyBurnedQuery)
        }
        sendPayload(
            MirroredWorkoutPayload(
                kind: .ended,
                endTime: Date(),
                energyBurned: currentEnergyBurned,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )
        )
        session?.end()
        builder?.endCollection(withEnd: Date()) { _, _ in
            self.builder?.finishWorkout { workout, _ in
                print("workout finished: \(String(describing: workout))")
            }
        }
    }

    /// Sends a mirrored jump update to the iPhone companion app.
    func sendJumpUpdate(jumpCount: Int, jumpOffset: TimeInterval) {
        sendPayload(
            MirroredWorkoutPayload(
                kind: .jump,
                jumpCount: jumpCount,
                jumpOffset: jumpOffset
            )
        )
    }

    // MARK: - Live Queries

    /// Starts the live heart-rate query for the active workout.
    private func startHeartRateQuery() {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, _, _, _, _ in
        }

        heartRateQuery?.updateHandler = { _, samples, _, _, _ in
            if let samples = samples as? [HKQuantitySample] {
                for sample in samples {
                    let bpm = sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
                    print("heartrate: \(bpm) bpm")
                    let heartRate = Int(bpm)
                    self.heartRateSum += heartRate
                    self.heartRateSamples += 1
                    self.averageHeartRate = self.heartRateSum / self.heartRateSamples
                    self.peakHeartRate = max(self.peakHeartRate ?? 0, heartRate)
                    self.updateHeartRate(heartRate)
                }
            }
        }
        if let heartRateQuery {
            healthStore.execute(heartRateQuery)
        }
    }

    /// Starts the live energy-burned query for the active workout.
    private func startEnergyBurnedQuery() {
        let energyBurnedType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: Date(), end: nil, options: .strictStartDate)
        energyBurnedQuery = HKAnchoredObjectQuery(
            type: energyBurnedType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, _, _, _, _ in
        }

        energyBurnedQuery?.updateHandler = { _, samples, _, _, _ in
            if let samples = samples as? [HKQuantitySample] {
                for sample in samples {
                    let kcal = sample.quantity.doubleValue(for: HKUnit.kilocalorie())
                    self.updateEnergyBurned(kcal)
                    self.sendPayload(
                        MirroredWorkoutPayload(
                            kind: .metrics,
                            energyBurned: kcal,
                            averageHeartRate: self.averageHeartRate,
                            peakHeartRate: self.peakHeartRate
                        )
                    )
                }
            }
        }
        if let energyBurnedQuery {
            healthStore.execute(energyBurnedQuery)
        }
    }

    /// Returns the total active energy burned so far in the workout.
    private var currentEnergyBurned: Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }

        return builder?
            .statistics(for: energyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
    }

    /// Starts HealthKit workout mirroring and sends the initial payload to iPhone.
    private func startMirroring(startDate: Date, goalType: GoalType, goalValue: Int) {
        guard let session else { return }

        Task {
            do {
                try await session.startMirroringToCompanionDevice()
                sendPayload(
                    MirroredWorkoutPayload(
                        kind: .started,
                        startTime: startDate,
                        goalType: goalType,
                        goalValue: goalValue
                    )
                )
            } catch {
                print("Failed to start workout mirroring: \(error)")
            }
        }
    }

    /// Encodes and sends a mirrored workout payload to the iPhone app.
    private func sendPayload(_ payload: MirroredWorkoutPayload) {
        guard let session else { return }

        do {
            let data = try encoder.encode(payload)
            session.sendToRemoteWorkoutSession(data: data) { success, error in
                if let error {
                    print("Failed to send mirrored workout payload: \(error)")
                } else if !success {
                    print("Mirrored workout payload was not delivered")
                }
            }
        } catch {
            print("Failed to encode mirrored workout payload: \(error)")
        }
    }
}

// MARK: - HKWorkoutSessionDelegate

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from _: HKWorkoutSessionState,
                        date _: Date)
    {
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

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>)
    {
        print("1: collected health data types: \(collectedTypes)")
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        print("2: collected health data: \(workoutBuilder)")
    }
}
