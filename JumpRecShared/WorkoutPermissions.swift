import HealthKit

/// Keeps Settings and workout startup aligned on the Health data requested by this device.
enum WorkoutPermissions {
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
            HKObjectType.activitySummaryType(),
        ]
        #if os(iOS)
            types.insert(HKObjectType.workoutType())
        #endif
        return types
    }

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
    static func requestAuthorization(using healthStore: HKHealthStore) async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        guard try await requestStatus(using: healthStore) == .shouldRequest else { return }
        try await healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead)
    }
}
