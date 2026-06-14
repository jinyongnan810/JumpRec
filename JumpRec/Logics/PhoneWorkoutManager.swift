//
//  PhoneWorkoutManager.swift
//  JumpRec
//

import Foundation
import HealthKit

/// Manages the iPhone-side HealthKit workout session used for local tracking.
@MainActor
final class PhoneWorkoutManager: NSObject {
    /// Publishes live iPhone workout metrics back to app state.
    var onMetricsUpdated: ((_ caloriesBurned: Double, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?

    /// Errors thrown when workout authorization is missing.
    private enum AuthorizationError: LocalizedError {
        case workoutWriteDenied

        /// Returns a user-facing description for the authorization failure.
        var errorDescription: String? {
            switch self {
            case .workoutWriteDenied:
                "Workout write permission is not granted."
            }
        }
    }

    /// Shared singleton used by app state.
    static let shared = PhoneWorkoutManager()

    /// ⭐️The HealthKit store used for authorization and workout creation.
    private let healthStore = HKHealthStore()
    /// Holds the active iOS 26 workout implementation when available.
    private var workoutStore: AnyObject?
    /// Deduplicates in-flight authorization requests.
    private var authorizationTask: Task<Void, Error>?

    /// Restricts creation to the shared singleton.
    override private init() {
        super.init()
    }

    /// Primes workout authorization early in the app lifecycle.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        authorizationTask = Task {
            try await ensureAuthorization()
        }
    }

    /// Starts a HealthKit workout session at the provided time.
    func startWorkout(at startDate: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard #available(iOS 26.0, *) else {
            print("[PhoneWorkoutManager] iPhone workout sessions require iOS 26 or newer.")
            return
        }

        print("[PhoneWorkoutManager] Starting workout at \(startDate)")
        try await ensureAuthorization()
        print("[PhoneWorkoutManager] Authorization ready for workout start.")

        if workoutStore == nil {
            workoutStore = PhoneWorkoutStore(
                healthStore: healthStore,
                onMetricsUpdated: onMetricsUpdated
            )
        }
        try await (workoutStore as? PhoneWorkoutStore)?.startWorkout(at: startDate)
        print("[PhoneWorkoutManager] Workout start request completed.")
    }

    /// Ends the active HealthKit workout session.
    func endWorkout(at endDate: Date) async {
        guard #available(iOS 26.0, *) else { return }
        print("[PhoneWorkoutManager] Ending workout at \(endDate)")
        await (workoutStore as? PhoneWorkoutStore)?.endWorkout(at: endDate)
        workoutStore = nil
        print("[PhoneWorkoutManager] Workout finish request completed.")
    }

    /// Discards the active workout without saving it.
    func discardWorkout() {
        guard #available(iOS 26.0, *) else { return }
        print("[PhoneWorkoutManager] Discarding active workout.")
        (workoutStore as? PhoneWorkoutStore)?.discardWorkout()
        workoutStore = nil
    }

    /// Ensures the app has requested every HealthKit permission used by iPhone workouts and mirroring.
    ///
    /// This method has internal visibility so the mirroring manager can share the same retained task.
    /// Keeping one authorization owner prevents two startup services from racing separate system sheets.
    func ensureAuthorization() async throws {
        if let authorizationTask {
            try await authorizationTask.value
            return
        }

        let task = Task {
            try await requestAuthorizationIfNeeded()
        }
        authorizationTask = task

        do {
            try await task.value
        } catch {
            authorizationTask = nil
            throw error
        }
    }

    /// Requests HealthKit authorization only when at least one required type is still undetermined.
    private func requestAuthorizationIfNeeded() async throws {
        let typesToShare: Set<HKSampleType> = [
            HKObjectType.workoutType(),
        ]

        // Keep this list as the union of local-workout and mirrored-workout requirements. HealthKit
        // does not reveal read authorization for privacy reasons, so the request-status API is the
        // supported way to determine whether the system still needs to ask about any read type.
        let typesToRead: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
            HKObjectType.activitySummaryType(),
        ]

        let requestStatus = try await authorizationRequestStatus(
            toShare: typesToShare,
            read: typesToRead
        )
        if requestStatus == .shouldRequest {
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        }

        // Write authorization is visible and required to save an iPhone workout. Read authorization
        // intentionally is not exposed by HealthKit; denied reads simply return no protected data.
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard status == .sharingAuthorized else {
            print("[PhoneWorkoutManager] Workout write authorization status: \(status.rawValue)")
            throw AuthorizationError.workoutWriteDenied
        }

        print("[PhoneWorkoutManager] HealthKit authorization is ready.")
    }

    /// Bridges HealthKit's callback-only request-status check into the structured authorization task.
    private func authorizationRequestStatus(
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
}

@available(iOS 26.0, *)
private final class PhoneWorkoutStore: NSObject {
    private let healthStore: HKHealthStore
    private let onMetricsUpdated: ((_ caloriesBurned: Double, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    init(
        healthStore: HKHealthStore,
        onMetricsUpdated: ((_ caloriesBurned: Double, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?
    ) {
        self.healthStore = healthStore
        self.onMetricsUpdated = onMetricsUpdated
    }

    func startWorkout(at startDate: Date) async throws {
        if session != nil {
            print("[PhoneWorkoutManager] Existing workout detected. Ending it before starting a new one.")
            await endWorkout(at: Date())
        }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

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
        try await builder.beginCollection(at: startDate)
        print("[PhoneWorkoutManager] HKWorkoutSession and builder started.")
    }

    func endWorkout(at endDate: Date) async {
        guard let session, let builder else { return }

        session.end()

        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
            print("[PhoneWorkoutManager] HKWorkoutSession finished and workout saved.")
        } catch {
            print("[PhoneWorkoutManager] Failed to finish workout: \(error)")
        }

        if self.session === session {
            self.session = nil
        }
        if self.builder === builder {
            self.builder = nil
        }
    }

    func discardWorkout() {
        session?.end()
        session = nil
        builder = nil
    }

    @MainActor
    private func publishMetrics(caloriesBurned: Double, averageHeartRate: Int?, peakHeartRate: Int?) {
        onMetricsUpdated?(caloriesBurned, averageHeartRate, peakHeartRate)
    }
}

@available(iOS 26.0, *)
extension PhoneWorkoutStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didChangeTo _: HKWorkoutSessionState,
                                    from _: HKWorkoutSessionState,
                                    date _: Date)
    {}

    nonisolated func workoutSession(_: HKWorkoutSession, didFailWithError error: Error) {
        print("[PhoneWorkoutManager] Workout session error: \(error)")
    }
}

@available(iOS 26.0, *)
extension PhoneWorkoutStore: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate)
        let energyBurnedType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)
        let shouldRefreshMetrics = collectedTypes.contains { sampleType in
            guard let quantityType = sampleType as? HKQuantityType else { return false }
            return quantityType == heartRateType || quantityType == energyBurnedType
        }

        guard shouldRefreshMetrics else { return }

        let heartRateUnit = HKUnit.count().unitDivided(by: .minute())
        let heartRateStatistics = heartRateType.flatMap { workoutBuilder.statistics(for: $0) }
        let averageHeartRate = heartRateStatistics?
            .averageQuantity()?
            .doubleValue(for: heartRateUnit)
            .rounded()
        let peakHeartRate = heartRateStatistics?
            .maximumQuantity()?
            .doubleValue(for: heartRateUnit)
            .rounded()
        let caloriesBurned = energyBurnedType
            .flatMap { workoutBuilder.statistics(for: $0) }?
            .sumQuantity()?
            .doubleValue(for: .kilocalorie()) ?? 0

        Task { @MainActor [weak self] in
            self?.publishMetrics(
                caloriesBurned: caloriesBurned,
                averageHeartRate: averageHeartRate.map(Int.init),
                peakHeartRate: peakHeartRate.map(Int.init)
            )
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_: HKLiveWorkoutBuilder) {}
}
