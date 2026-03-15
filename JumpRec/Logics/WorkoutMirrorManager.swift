//
//  WorkoutMirrorManager.swift
//  JumpRec
//

import Foundation
import HealthKit

/// Manages HealthKit workout mirroring between Apple Watch and iPhone.
@MainActor
final class WorkoutMirrorManager: NSObject {
    /// Shared singleton used by app state.
    static let shared = WorkoutMirrorManager()

    /// Delivers decoded mirrored payloads to app state.
    var onPayloadReceived: ((MirroredWorkoutPayload) -> Void)?
    /// Notifies app state when the mirrored session ends.
    var onMirroredSessionEnded: (() -> Void)?

    // The iPhone must own an HKHealthStore to participate in HealthKit workout mirroring.
    // This is separate from WatchConnectivity:
    // - WCSession is for general app/watch messaging.
    // - HKWorkoutSession mirroring is for an active HealthKit workout and lets the system
    //   wake the companion iPhone app, attach a mirrored session, and deliver workout data.
    /// The HealthKit store used for mirroring registration.
    private let healthStore = HKHealthStore()
    /// Decodes mirrored payloads coming from the watch.
    private let decoder = JSONDecoder()
    /// Tracks the currently attached mirrored workout session.
    private var mirroredSession: HKWorkoutSession?

    /// Restricts creation to the shared singleton.
    override private init() {
        super.init()
        decoder.dateDecodingStrategy = .deferredToDate
    }

    /// Requests the system to launch the companion watch workout.
    func startCompanionWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

        try await healthStore.startWatchApp(toHandle: configuration)
    }

    /// Registers mirroring callbacks and requests HealthKit authorization.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Register this as early as possible so the iPhone can receive a mirrored workout
        // session started from Apple Watch, even if the iOS app is launched in background.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.attachMirroredSession(session)
            }
        }

        requestAuthorization()
    }

    /// Requests the HealthKit permissions required for workout mirroring.
    private func requestAuthorization() {
        // Read permission is still required on iPhone because the mirrored workout session is
        // a HealthKit workflow, not just a transport channel for arbitrary watch messages.
        let readTypes: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!,
            HKQuantityType.quantityType(forIdentifier: .heartRate)!,
        ]

        healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
            if let error {
                print("[WorkoutMirrorManager] Authorization failed: \(error)")
            } else {
                print("[WorkoutMirrorManager] Authorization success: \(success)")
            }
        }
    }

    /// Attaches the mirrored workout session so payloads can be received.
    private func attachMirroredSession(_ session: HKWorkoutSession) {
        // Keep a reference to the mirrored session so the iPhone can receive payloads sent with
        // sendToRemoteWorkoutSession(data:) from the watch's primary HKWorkoutSession.
        mirroredSession = session
        mirroredSession?.delegate = self
    }
}

extension WorkoutMirrorManager: HKWorkoutSessionDelegate {
    /// Decodes mirrored workout payloads received from Apple Watch.
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data])
    {
        // HealthKit may batch multiple payloads before delivering them to iPhone,
        // especially when the iOS app was suspended in background.
        for payloadData in data {
            Task { @MainActor [weak self] in
                guard let self else { return }

                do {
                    let payload = try decoder.decode(MirroredWorkoutPayload.self, from: payloadData)
                    onPayloadReceived?(payload)
                } catch {
                    print("[WorkoutMirrorManager] Failed to decode mirrored payload: \(error)")
                }
            }
        }
    }

    /// Clears mirrored-session state when the watch workout ends.
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession,
                                    didChangeTo toState: HKWorkoutSessionState,
                                    from _: HKWorkoutSessionState,
                                    date _: Date)
    {
        guard toState == .ended else { return }

        Task { @MainActor in
            if self.mirroredSession == workoutSession {
                self.mirroredSession = nil
            }
            self.onMirroredSessionEnded?()
        }
    }

    /// Logs HealthKit mirroring failures.
    nonisolated func workoutSession(_: HKWorkoutSession, didFailWithError error: Error) {
        print("[WorkoutMirrorManager] Mirrored session error: \(error)")
    }
}
