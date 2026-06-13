//
//  WorkoutManager.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/03/01.
//

import Foundation
import HealthKit

/// Manages HealthKit workout sessions, heart rate, and energy burned tracking.
@MainActor
final class WorkoutManager: NSObject {
    /// Errors produced when HealthKit reports an unsuccessful callback without an error object.
    private enum WorkoutFinalizationError: LocalizedError {
        case endCollectionFailed

        var errorDescription: String? {
            "HealthKit could not end workout data collection."
        }
    }

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
    /// Deduplicates an in-flight HealthKit authorization request.
    private var authorizationTask: Task<Void, Error>?
    /// Owns asynchronous startup or finishing work for the current workout.
    private var workoutLifecycleTask: Task<Void, Never>?
    /// Identifies the workout that owns asynchronous HealthKit completions.
    private var workoutGeneration = UUID()

    // MARK: - Initialization

    /// Requests authorization and stores callbacks for workout metrics.
    init(updateHeartRate: @escaping (Int) -> Void, updateEnergyBurned: @escaping (Double) -> Void) {
        self.updateHeartRate = updateHeartRate
        self.updateEnergyBurned = updateEnergyBurned
        super.init()

        // Prime authorization early. Workout startup awaits the same retained task, so
        // multiple callers never present overlapping HealthKit permission requests.
        authorizationTask = Task { [healthStore] in
            try await Self.requestAuthorization(using: healthStore)
        }
    }

    // MARK: - Authorization

    /// Waits for the current authorization request or starts one when needed.
    private func ensureAuthorization() async throws {
        if let authorizationTask {
            try await authorizationTask.value
            return
        }

        let task = Task { [healthStore] in
            try await Self.requestAuthorization(using: healthStore)
        }
        authorizationTask = task

        do {
            try await task.value
        } catch {
            authorizationTask = nil
            throw error
        }
    }

    /// Requests the HealthKit permissions required by the watch workout.
    private nonisolated static func requestAuthorization(using healthStore: HKHealthStore) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
        ]

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        print("[WorkoutManager] HealthKit authorization request completed")
    }

    // MARK: - Workout Session

    /// Starts a jump-rope workout and begins mirroring it to the iPhone app.
    func startWorkout(startDate: Date, goalType: GoalType, goalValue: Int) {
        workoutGeneration = UUID()
        let generation = workoutGeneration
        workoutLifecycleTask?.cancel()
        stopLiveQueries()

        averageHeartRate = nil
        peakHeartRate = nil
        heartRateSum = 0
        heartRateSamples = 0

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

        do {
            let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore,
                workoutConfiguration: configuration
            )
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            session.startActivity(with: startDate)

            workoutLifecycleTask = Task { [weak self] in
                guard let self else { return }

                do {
                    try await ensureAuthorization()
                    try Task.checkCancellation()
                    try await builder.beginCollection(at: startDate)
                    try Task.checkCancellation()
                    try await session.startMirroringToCompanionDevice()
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    print("[WorkoutManager] Failed to start workout collection: \(error.localizedDescription)")
                    return
                }

                guard workoutGeneration == generation,
                      self.session === session,
                      self.builder === builder
                else {
                    return
                }

                sendPayload(
                    MirroredWorkoutPayload(
                        kind: .started,
                        startTime: startDate,
                        goalType: goalType,
                        goalValue: goalValue
                    )
                )
                startHeartRateQuery(startDate: startDate)
                startEnergyBurnedQuery(startDate: startDate)
            }
        } catch {
            print("[WorkoutManager] Failed to create workout session: \(error.localizedDescription)")
        }
    }

    /// Ends the workout, sends final mirrored metrics, and saves it to HealthKit.
    func stopWorkout() {
        workoutGeneration = UUID()
        workoutLifecycleTask?.cancel()
        workoutLifecycleTask = nil
        stopLiveQueries()

        let endDate = Date()
        sendPayload(
            MirroredWorkoutPayload(
                kind: .ended,
                endTime: endDate,
                energyBurned: currentEnergyBurned,
                averageHeartRate: averageHeartRate,
                peakHeartRate: peakHeartRate
            )
        )

        guard let session, let builder else {
            self.session = nil
            self.builder = nil
            return
        }

        session.end()
        self.session = nil
        self.builder = nil

        workoutLifecycleTask = Task {
            do {
                try await endCollection(builder, at: endDate)
                let workout = try await finishWorkout(builder)
                print("[WorkoutManager] Workout finished: \(String(describing: workout))")
            } catch is CancellationError {
                return
            } catch {
                print("[WorkoutManager] Failed to finish workout: \(error.localizedDescription)")
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
    private func startHeartRateQuery(startDate: Date) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        heartRateQuery = HKAnchoredObjectQuery(
            type: heartRateType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, _, _, _, _ in
        }

        heartRateQuery?.updateHandler = { [weak self] _, samples, _, _, error in
            if let error {
                print("[WorkoutManager] Heart-rate query failed: \(error.localizedDescription)")
                return
            }

            let heartRates = (samples as? [HKQuantitySample])?.map { sample in
                Int(sample.quantity.doubleValue(for: HKUnit.count().unitDivided(by: .minute())))
            } ?? []
            guard !heartRates.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.applyHeartRates(heartRates)
            }
        }
        if let heartRateQuery {
            healthStore.execute(heartRateQuery)
        }
    }

    /// Starts the live energy-burned query for the active workout.
    private func startEnergyBurnedQuery(startDate: Date) {
        let energyBurnedType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: nil, options: .strictStartDate)
        energyBurnedQuery = HKAnchoredObjectQuery(
            type: energyBurnedType,
            predicate: predicate,
            anchor: nil,
            limit: HKObjectQueryNoLimit
        ) { _, _, _, _, _ in
        }

        energyBurnedQuery?.updateHandler = { [weak self] _, samples, _, _, error in
            if let error {
                print("[WorkoutManager] Energy query failed: \(error.localizedDescription)")
                return
            }

            let energyValues = (samples as? [HKQuantitySample])?.map { sample in
                sample.quantity.doubleValue(for: .kilocalorie())
            } ?? []
            guard !energyValues.isEmpty else { return }

            Task { @MainActor [weak self] in
                self?.applyEnergyValues(energyValues)
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

    /// Applies heart-rate samples after crossing back from HealthKit's query callback.
    private func applyHeartRates(_ heartRates: [Int]) {
        for heartRate in heartRates {
            heartRateSum += heartRate
            heartRateSamples += 1
            averageHeartRate = heartRateSum / heartRateSamples
            peakHeartRate = max(peakHeartRate ?? 0, heartRate)
            updateHeartRate(heartRate)
        }
    }

    /// Applies energy samples and mirrors the latest aggregate metrics to iPhone.
    private func applyEnergyValues(_ energyValues: [Double]) {
        for energyBurned in energyValues {
            updateEnergyBurned(energyBurned)
            sendPayload(
                MirroredWorkoutPayload(
                    kind: .metrics,
                    energyBurned: energyBurned,
                    averageHeartRate: averageHeartRate,
                    peakHeartRate: peakHeartRate
                )
            )
        }
    }

    /// Stops and releases HealthKit queries owned by the current workout.
    private func stopLiveQueries() {
        if let heartRateQuery {
            healthStore.stop(heartRateQuery)
            self.heartRateQuery = nil
        }
        if let energyBurnedQuery {
            healthStore.stop(energyBurnedQuery)
            self.energyBurnedQuery = nil
        }
    }

    /// Bridges callback-only collection ending into the structured stop task.
    private func endCollection(_ builder: HKLiveWorkoutBuilder, at endDate: Date) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            builder.endCollection(withEnd: endDate) { success, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: WorkoutFinalizationError.endCollectionFailed)
                }
            }
        }
    }

    /// Bridges callback-only workout saving into the structured stop task.
    private func finishWorkout(_ builder: HKLiveWorkoutBuilder) async throws -> HKWorkout? {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<HKWorkout?, Error>) in
            builder.finishWorkout { workout, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: workout)
                }
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
    nonisolated func workoutSession(_: HKWorkoutSession,
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

    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didFailWithError error: Error)
    {
        print("workout session error: \(error.localizedDescription)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_: HKLiveWorkoutBuilder,
                                    didCollectDataOf collectedTypes: Set<HKSampleType>)
    {
        print("1: collected health data types: \(collectedTypes)")
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {
        print("2: collected health data: \(workoutBuilder)")
    }
}
