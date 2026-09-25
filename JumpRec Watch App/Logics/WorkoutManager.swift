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
    /// Encodes mirrored payloads sent to the iPhone app.
    private let encoder = JSONEncoder()
    /// Tracks whether HealthKit successfully created a companion iPhone mirror.
    ///
    /// Watch-only workouts must keep collecting local HealthKit data even when the user
    /// leaves the iPhone behind. Keeping this flag false until mirroring succeeds lets
    /// jump and metric updates avoid a stream of expected remote-send failures.
    private var isMirroringActive = false
    /// Stores the current average heart rate for mirrored updates.
    private var averageHeartRate: Int?
    /// Stores the current peak heart rate for mirrored updates.
    private var peakHeartRate: Int?
    /// Deduplicates an in-flight HealthKit authorization request.
    private var authorizationTask: Task<Void, Error>?
    /// Owns asynchronous startup or finishing work for the current workout.
    private var workoutLifecycleTask: Task<Void, Never>?
    /// Identifies the workout that owns asynchronous HealthKit completions.
    private var workoutGeneration = UUID()
    /// Minimum time interval between mirrored jump updates to prevent continuous radio transmission.
    private let minMirroredJumpInterval: TimeInterval = 1.0
    /// Timestamp of the last mirrored jump update transmitted to the companion device.
    private var lastMirroredJumpSentAt: Date = .distantPast
    /// Stores the latest pending jump payload when updates are throttled.
    private var pendingMirroredJumpPayload: MirroredWorkoutPayload?
    /// Owns the timer task that delivers the latest pending jump update after the throttle window elapses.
    private var throttledJumpTask: Task<Void, Never>?

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

    /// Requests the HealthKit permissions required by the watch workout when still undetermined.
    private nonisolated static func requestAuthorization(using healthStore: HKHealthStore) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
        ]

        let typesToRead: Set<HKObjectType> = [
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
        ]

        // requestAuthorization is safe after a previous decision, but checking first avoids asking
        // watchOS to begin an authorization presentation every time AppState recreates this manager.
        let requestStatus = try await authorizationRequestStatus(
            using: healthStore,
            toShare: typesToShare,
            read: typesToRead
        )
        guard requestStatus == .shouldRequest else {
            print("[WorkoutManager] HealthKit authorization was already requested")
            return
        }

        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        print("[WorkoutManager] HealthKit authorization request completed")
    }

    /// Bridges HealthKit's callback-only request-status API into the retained authorization task.
    private nonisolated static func authorizationRequestStatus(
        using healthStore: HKHealthStore,
        toShare typesToShare: Set<HKSampleType>,
        read typesToRead: Set<HKObjectType>
    ) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(
                toShare: typesToShare,
                read: typesToRead
            ) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    // MARK: - Workout Session

    /// Starts a jump-rope workout locally and attempts to mirror it to the iPhone app.
    func startWorkout(startDate: Date, goalType: GoalType, goalValue: Int) {
        workoutGeneration = UUID()
        let generation = workoutGeneration
        workoutLifecycleTask?.cancel()
        throttledJumpTask?.cancel()
        throttledJumpTask = nil
        pendingMirroredJumpPayload = nil
        lastMirroredJumpSentAt = .distantPast

        isMirroringActive = false
        averageHeartRate = nil
        peakHeartRate = nil

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

                do {
                    try await session.startMirroringToCompanionDevice()
                    try Task.checkCancellation()
                } catch is CancellationError {
                    return
                } catch {
                    // A missing or unreachable iPhone should not break a watch-only workout.
                    // Local collection is already running, so keep the session alive and skip
                    // remote payloads until a future workout creates a mirror successfully.
                    isMirroringActive = false
                    print("[WorkoutManager] Companion mirroring unavailable: \(error.localizedDescription)")
                    return
                }

                guard workoutGeneration == generation,
                      self.session === session,
                      self.builder === builder
                else {
                    return
                }

                isMirroringActive = true
                sendPayload(
                    MirroredWorkoutPayload(
                        kind: .started,
                        startTime: startDate,
                        goalType: goalType,
                        goalValue: goalValue
                    )
                )
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
        throttledJumpTask?.cancel()
        throttledJumpTask = nil
        pendingMirroredJumpPayload = nil

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
        isMirroringActive = false

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

    /// Sends a mirrored jump update to the iPhone companion app, including latest cumulative metrics.
    ///
    /// Jumps occur multiple times per second (e.g., 2–3 Hz). Transmitting Bluetooth radio packets on
    /// every single jump keeps the watch wireless chip continuously powered on. This method throttles
    /// transmissions to at most once per second while ensuring the trailing jump count is always delivered.
    func sendJumpUpdate(jumpCount: Int, jumpOffset: TimeInterval) {
        let totalEnergyBurned = currentEnergyBurned
        let payload = MirroredWorkoutPayload(
            kind: .jump,
            jumpCount: jumpCount,
            jumpOffset: jumpOffset,
            energyBurned: totalEnergyBurned,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRate
        )

        pendingMirroredJumpPayload = payload

        let elapsed = Date().timeIntervalSince(lastMirroredJumpSentAt)
        if elapsed >= minMirroredJumpInterval, throttledJumpTask == nil {
            lastMirroredJumpSentAt = Date()
            pendingMirroredJumpPayload = nil
            sendPayload(payload)
        } else if throttledJumpTask == nil {
            let remainingDelay = max(0.1, minMirroredJumpInterval - elapsed)
            throttledJumpTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(remainingDelay))
                } catch {
                    return
                }

                guard let self, !Task.isCancelled else { return }
                throttledJumpTask = nil
                if let pending = pendingMirroredJumpPayload {
                    pendingMirroredJumpPayload = nil
                    lastMirroredJumpSentAt = Date()
                    sendPayload(pending)
                }
            }
        }
    }

    // MARK: - HealthKit Metrics Processing

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

    /// Processes newly collected health samples delivered by HKLiveWorkoutBuilder.
    ///
    /// Relying on HKLiveWorkoutDataSource and HKLiveWorkoutBuilder's native statistics calculations
    /// avoids running redundant HKAnchoredObjectQuery instances against the HealthKit store,
    /// significantly reducing background database queries and CPU wakeups on Apple Watch.
    func processCollectedData(from workoutBuilder: HKLiveWorkoutBuilder, types: Set<HKSampleType>) {
        guard builder === workoutBuilder else { return }

        var metricsChanged = false

        if let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate),
           types.contains(heartRateType),
           let statistics = workoutBuilder.statistics(for: heartRateType)
        {
            let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
            if let mostRecent = statistics.mostRecentQuantity() {
                let latestHR = Int(mostRecent.doubleValue(for: heartRateUnit))
                updateHeartRate(latestHR)
            }
            if let average = statistics.averageQuantity() {
                averageHeartRate = Int(average.doubleValue(for: heartRateUnit))
            }
            if let maximum = statistics.maximumQuantity() {
                peakHeartRate = Int(maximum.doubleValue(for: heartRateUnit))
            }
            metricsChanged = true
        }

        if let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
           types.contains(energyType),
           let statistics = workoutBuilder.statistics(for: energyType),
           let sum = statistics.sumQuantity()
        {
            let totalEnergy = sum.doubleValue(for: .kilocalorie())
            updateEnergyBurned(totalEnergy)
            metricsChanged = true
        }

        if metricsChanged {
            sendPayload(
                MirroredWorkoutPayload(
                    kind: .metrics,
                    energyBurned: currentEnergyBurned,
                    averageHeartRate: averageHeartRate,
                    peakHeartRate: peakHeartRate
                )
            )
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
        guard isMirroringActive, let session else { return }

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
    nonisolated func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        Task { @MainActor [weak self] in
            self?.processCollectedData(from: workoutBuilder, types: collectedTypes)
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_: HKLiveWorkoutBuilder) {}
}
