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

    var updateHeartRate: (Int) -> Void
    var updateEnergyBurned: (Double) -> Void

    // MARK: - HealthKit State

    private let healthStore = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var heartRateQuery: HKAnchoredObjectQuery?
    private var energyBurnedQuery: HKAnchoredObjectQuery?

    // MARK: - Initialization

    init(updateHeartRate: @escaping (Int) -> Void, updateEnergyBurned: @escaping (Double) -> Void) {
        self.updateHeartRate = updateHeartRate
        self.updateEnergyBurned = updateEnergyBurned
        super.init()
        requestAuthorization()
    }

    // MARK: - Authorization

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

    func startWorkout() {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor
        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            builder = session?.associatedWorkoutBuilder()

            session?.delegate = self
            builder?.delegate = self

            let startDate = Date()
            session?.startActivity(with: startDate)
            builder?.beginCollection(withStart: startDate) { success, error in
                print("Collecting health data started: \(success)")
                if let error {
                    print("Failed to start collecting health data: \(error)")
                }

                self.startHeartRateQuery()
                self.startEnergyBurnedQuery()
            }
        } catch {
            print("Collecting health data failed")
        }
    }

    func stopWorkout() {
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
        }
        if let energyBurnedQuery {
            healthStore.stop(energyBurnedQuery)
        }
        session?.end()
        builder?.endCollection(withEnd: Date()) { _, _ in
            self.builder?.finishWorkout { workout, _ in
                print("workout finished: \(String(describing: workout))")
            }
        }
    }

    // MARK: - Live Queries

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
                    self.updateHeartRate(Int(bpm))
                }
            }
        }
        if let heartRateQuery {
            healthStore.execute(heartRateQuery)
        }
    }

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
                }
            }
        }
        if let energyBurnedQuery {
            healthStore.execute(energyBurnedQuery)
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
