//
//  WorkoutManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/03/01.
//

import Foundation
import HealthKit
import JumpRecShared

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
    private let encoder = JSONEncoder()
    private var averageHeartRate: Int?
    private var peakHeartRate: Int?
    private var heartRateSum = 0
    private var heartRateSamples = 0

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

    private var currentEnergyBurned: Double {
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            return 0
        }

        return builder?
            .statistics(for: energyType)?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0
    }

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
