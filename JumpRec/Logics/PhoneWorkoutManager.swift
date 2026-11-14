//
//  PhoneWorkoutManager.swift
//  JumpRec
//

import Foundation
import HealthKit

/// Manages the iPhone-side HealthKit workout session used for local tracking.
@MainActor
final class PhoneWorkoutManager: NSObject {
    // MARK: - Public API

    /// Publishes live iPhone workout metrics back to app state.
    var onMetricsUpdated: ((_ caloriesBurned: Double, _ heartRate: Int?, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?

    /// Errors thrown when workout authorization is missing.
    private enum AuthorizationError: LocalizedError {
        case workoutWriteDenied

        /// Returns a user-facing description for the authorization failure.
        var errorDescription: String? {
            switch self {
            case .workoutWriteDenied:
                String(localized: "Workout write permission is not granted.")
            }
        }
    }

    /// Shared singleton used by app state.
    static let shared = PhoneWorkoutManager()

    // MARK: - Stored Properties

    /// ⭐️The HealthKit store used for authorization and workout creation.
    private let healthStore = HKHealthStore()
    /// Holds the iOS 26+ `PhoneWorkoutStore` as `AnyObject` so stored properties compile on earlier OS versions.
    private var workoutStore: AnyObject?
    /// Builds and saves local workouts on iOS versions that predate iPhone workout sessions.
    private var workoutBuilder: HKWorkoutBuilder?
    /// Deduplicates in-flight authorization requests.
    private var authorizationTask: Task<Void, Error>?

    // MARK: - Initialization

    /// Restricts creation to the shared singleton.
    override private init() {
        super.init()
    }

    // MARK: - Workout Lifecycle

    /// Creates and prepares a HealthKit workout session during the pre-session countdown.
    func prepareWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        try await ensureAuthorization()

        let configuration = makeWorkoutConfiguration()
        if #available(iOS 26.0, *) {
            if workoutStore == nil {
                workoutStore = PhoneWorkoutStore(
                    healthStore: healthStore,
                    onMetricsUpdated: onMetricsUpdated
                )
            }
            try await (workoutStore as? PhoneWorkoutStore)?.prepareWorkout(
                configuration: configuration
            )
        } else if workoutBuilder == nil {
            // Pre-allocate the builder during the countdown so start only begins collection.
            workoutBuilder = HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: configuration,
                device: .local()
            )
        }
    }

    /// Starts a HealthKit workout at the provided time, reusing any session prepared during the countdown.
    func startWorkout(at startDate: Date) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        print("[PhoneWorkoutManager] Starting workout at \(startDate)")
        try await ensureAuthorization()
        print("[PhoneWorkoutManager] Authorization ready for workout start.")

        let configuration = makeWorkoutConfiguration()
        if #available(iOS 26.0, *) {
            if workoutStore == nil {
                workoutStore = PhoneWorkoutStore(
                    healthStore: healthStore,
                    onMetricsUpdated: onMetricsUpdated
                )
            }
            try await (workoutStore as? PhoneWorkoutStore)?.startWorkout(
                at: startDate,
                configuration: configuration
            )
        } else {
            // Before iOS 26, reuse the prepared builder or create one to save the workout to Health.
            let builder = workoutBuilder ?? HKWorkoutBuilder(
                healthStore: healthStore,
                configuration: configuration,
                device: .local()
            )
            workoutBuilder = builder
            try await builder.beginCollection(at: startDate)
        }

        print("[PhoneWorkoutManager] Workout start request completed.")
    }

    /// Ends and saves the active HealthKit workout.
    func endWorkout(at endDate: Date) async {
        print("[PhoneWorkoutManager] Ending workout at \(endDate)")

        if #available(iOS 26.0, *) {
            let activeStore = workoutStore as? PhoneWorkoutStore
            await activeStore?.endWorkout(at: endDate)
            if workoutStore === activeStore, activeStore?.hasSession == false {
                workoutStore = nil
            }
        } else if let workoutBuilder {
            do {
                try await workoutBuilder.endCollection(at: endDate)
                _ = try await workoutBuilder.finishWorkout()
                print("[PhoneWorkoutManager] HKWorkoutBuilder finished and workout saved.")
            } catch {
                print("[PhoneWorkoutManager] Failed to save workout: \(error)")
            }
            self.workoutBuilder = nil
        }

        print("[PhoneWorkoutManager] Workout finish request completed.")
    }

    /// Discards any prepared or active workout without saving it to HealthKit.
    func discardWorkout() {
        print("[PhoneWorkoutManager] Discarding active workout.")
        if #available(iOS 26.0, *) {
            (workoutStore as? PhoneWorkoutStore)?.discardWorkout()
            workoutStore = nil
        }

        // Releasing an unfinished builder discards the unsaved workout before iOS 26.
        workoutBuilder = nil
    }

    // MARK: - Helpers & Authorization

    /// Creates the configuration shared by live and builder-only iPhone workout implementations.
    private func makeWorkoutConfiguration() -> HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor
        return configuration
    }

    /// Shares one HealthKit authorization task between local workouts and mirroring.
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
        try await WorkoutPermissions.requestAuthorization(using: healthStore)

        // Check write authorization; denied reads return no data and expose no authorization status.
        let status = healthStore.authorizationStatus(for: HKObjectType.workoutType())
        guard status == .sharingAuthorized else {
            print("[PhoneWorkoutManager] Workout write authorization status: \(status.rawValue)")
            throw AuthorizationError.workoutWriteDenied
        }

        print("[PhoneWorkoutManager] HealthKit authorization is ready.")
    }
}

/// Wraps iOS 26+ `HKWorkoutSession` and `HKLiveWorkoutBuilder` APIs for local iPhone workouts.
@available(iOS 26.0, *)
private final class PhoneWorkoutStore: NSObject {
    // MARK: - Stored Properties

    /// Shared HealthKit store used to create sessions and live data sources.
    private let healthStore: HKHealthStore
    /// Forwards live calorie and heart-rate statistics to `PhoneWorkoutManager`.
    private let onMetricsUpdated: ((_ caloriesBurned: Double, _ heartRate: Int?, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?
    /// Tracks the current prepared or active workout session.
    private var session: HKWorkoutSession?
    /// Collects live samples and builds the final workout for `session`.
    private var builder: HKLiveWorkoutBuilder?
    /// Distinguishes a pre-warmed `.prepared` session from one that has started recording activity.
    private var isActivityStarted = false

    /// Indicates whether a prepared or active workout session is currently owned by this store.
    var hasSession: Bool {
        session != nil
    }

    // MARK: - Initialization

    /// Creates a store bound to the shared HealthKit store and metrics callback.
    init(
        healthStore: HKHealthStore,
        onMetricsUpdated: ((_ caloriesBurned: Double, _ heartRate: Int?, _ averageHeartRate: Int?, _ peakHeartRate: Int?) -> Void)?
    ) {
        self.healthStore = healthStore
        self.onMetricsUpdated = onMetricsUpdated
    }

    // MARK: - Session Lifecycle

    /// Warms up HealthKit sensors in the `.prepared` state without starting sample collection.
    func prepareWorkout(configuration: HKWorkoutConfiguration) async throws {
        // Keep the existing session only when it is still waiting in `.prepared` or `.notStarted` state.
        if let session, !isActivityStarted, session.state == .prepared || session.state == .notStarted {
            return
        }
        if session != nil {
            await endWorkout(at: Date())
        }

        let (session, builder) = try makeSessionAndBuilder(configuration: configuration)
        self.session = session
        self.builder = builder
        isActivityStarted = false
        session.prepare()
    }

    /// Transitions a prepared session into active collection, or creates and starts a new session.
    func startWorkout(
        at startDate: Date,
        configuration: HKWorkoutConfiguration
    ) async throws {
        // Fast path: activate the session that was prepared during the countdown.
        if let session, let builder, !isActivityStarted, session.state == .prepared || session.state == .notStarted {
            isActivityStarted = true
            session.startActivity(with: startDate)
            try await builder.beginCollection(at: startDate)
            print("[PhoneWorkoutManager] Prepared HKWorkoutSession and builder started.")
            return
        }

        if session != nil {
            print("[PhoneWorkoutManager] Existing workout detected. Ending it before starting a new one.")
            await endWorkout(at: Date())
        }

        let (session, builder) = try makeSessionAndBuilder(configuration: configuration)
        self.session = session
        self.builder = builder
        isActivityStarted = true

        session.startActivity(with: startDate)
        try await builder.beginCollection(at: startDate)
        print("[PhoneWorkoutManager] HKWorkoutSession and builder started.")
    }

    /// Ends sample collection and saves the workout, or discards a session that never started.
    func endWorkout(at endDate: Date) async {
        guard let session, let builder else {
            isActivityStarted = false
            return
        }

        // A session that was only prepared has no collected activity to save.
        guard isActivityStarted else {
            discardWorkout()
            return
        }

        isActivityStarted = false
        // Detach references up front so a newly prepared workout cannot collide with this save.
        self.session = nil
        self.builder = nil
        defer {
            if session.state != .ended {
                session.end()
            }
        }

        if session.state == .running || session.state == .paused {
            session.stopActivity(with: endDate)
        }

        do {
            try await builder.endCollection(at: endDate)
            _ = try await builder.finishWorkout()
            print("[PhoneWorkoutManager] HKWorkoutSession finished and workout saved.")
        } catch {
            print("[PhoneWorkoutManager] Failed to finish workout: \(error)")
        }
    }

    /// Ends the current session immediately without saving a workout to HealthKit.
    func discardWorkout() {
        isActivityStarted = false
        if let session, session.state != .ended {
            session.end()
        }
        session = nil
        builder = nil
    }

    // MARK: - Helpers

    /// Creates a workout session, attaches its live builder and data source, and assigns delegates.
    private func makeSessionAndBuilder(
        configuration: HKWorkoutConfiguration
    ) throws -> (HKWorkoutSession, HKLiveWorkoutBuilder) {
        let session = try HKWorkoutSession(healthStore: healthStore, configuration: configuration)
        let builder = session.associatedWorkoutBuilder()
        builder.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: configuration
        )

        session.delegate = self
        builder.delegate = self
        return (session, builder)
    }

    /// Delivers updated live workout metrics on the main actor.
    @MainActor
    private func publishMetrics(caloriesBurned: Double, heartRate: Int?, averageHeartRate: Int?, peakHeartRate: Int?) {
        onMetricsUpdated?(caloriesBurned, heartRate, averageHeartRate, peakHeartRate)
    }
}

// MARK: - HKWorkoutSessionDelegate

@available(iOS 26.0, *)
extension PhoneWorkoutStore: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didChangeTo _: HKWorkoutSessionState,
                                    from _: HKWorkoutSessionState,
                                    date _: Date) {}

    nonisolated func workoutSession(_: HKWorkoutSession, didFailWithError error: Error) {
        print("[PhoneWorkoutManager] Workout session error: \(error)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate

@available(iOS 26.0, *)
extension PhoneWorkoutStore: HKLiveWorkoutBuilderDelegate {
    /// Reads updated heart-rate and active-energy statistics whenever HealthKit collects new samples.
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
        let heartRate = heartRateStatistics?
            .mostRecentQuantity()?
            .doubleValue(for: heartRateUnit)
            .rounded()
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
                heartRate: heartRate.map(Int.init),
                averageHeartRate: averageHeartRate.map(Int.init),
                peakHeartRate: peakHeartRate.map(Int.init)
            )
        }
    }

    nonisolated func workoutBuilderDidCollectEvent(_: HKLiveWorkoutBuilder) {}
}
