import CoreMotion
import HealthKit

/// Keeps Settings and workout startup aligned on the Health data requested by this device.
enum WorkoutPermissions {
    enum PreparationError: LocalizedError {
        case workoutAccessDenied
        case motionAccessDenied

        var errorDescription: String? {
            switch self {
            case .workoutAccessDenied:
                String(localized: "Allow JumpRec to save workouts in Health before starting. Review access in JumpRec Settings.")
            case .motionAccessDenied:
                String(localized: "Allow Motion & Fitness access in JumpRec’s system settings before starting a headphone workout.")
            }
        }
    }

    /// Resolves permission prompts before the countdown without starting workout collection.
    @MainActor
    static func prepareForWorkout(requestMotion: Bool = false) async throws {
        let healthStore = HKHealthStore()
        try await requestAuthorization(using: healthStore)
        try Task.checkCancellation()
        if HKHealthStore.isHealthDataAvailable(),
           healthStore.authorizationStatus(for: HKObjectType.workoutType()) != .sharingAuthorized
        {
            throw PreparationError.workoutAccessDenied
        }
        #if os(iOS)
            if requestMotion, CMMotionActivityManager.isActivityAvailable() {
                if CMMotionActivityManager.authorizationStatus() == .notDetermined {
                    let manager = CMMotionActivityManager()
                    let now = Date()
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        manager.queryActivityStarting(from: now, to: now, to: .main) { [manager] _, _ in
                            // An empty query may report no samples; only its permission decision is needed.
                            withExtendedLifetime(manager) { continuation.resume() }
                        }
                    }
                }
                try Task.checkCancellation()
                let status = CMMotionActivityManager.authorizationStatus()
                if status == .denied || status == .restricted {
                    throw PreparationError.motionAccessDenied
                }
            }
        #endif
    }

    static var typesToShare: Set<HKSampleType> {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        #if os(watchOS)
            types.insert(HKQuantityType(.activeEnergyBurned))
        #endif
        return types
    }

    static var typesToRead: Set<HKObjectType> {
        var types: Set<HKObjectType> = [
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.heartRate),
        ]
        #if os(iOS)
            types.insert(HKObjectType.workoutType())
        #endif
        return types
    }

    /// Deduplicates overlapping HealthKit authorization prompts across launch and workout start.
    @MainActor
    private static var authorizationTask: Task<Void, Error>?

    static func requestStatus(using healthStore: HKHealthStore) async throws -> HKAuthorizationRequestStatus {
        try await withCheckedThrowingContinuation { continuation in
            healthStore.getRequestStatusForAuthorization(toShare: typesToShare, read: typesToRead) { status, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: status)
                }
            }
        }
    }

    /// A completed request means the person answered, not that every permission was granted.
    @MainActor
    static func requestAuthorization(using healthStore: HKHealthStore) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        if let authorizationTask {
            try await authorizationTask.value
            return
        }

        let task = Task { @MainActor in
            guard try await requestStatus(using: healthStore) == .shouldRequest else { return }
            try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
        }
        authorizationTask = task
        defer { authorizationTask = nil }
        try await task.value
    }
}
