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

    /// HealthKit store required to register and receive mirrored workout sessions.
    private let healthStore = HKHealthStore()
    /// Decodes mirrored payloads coming from the watch.
    private let decoder = JSONDecoder()
    /// ⭐️Tracks the currently attached mirrored workout session.
    private var mirroredSession: HKWorkoutSession?

    /// Restricts creation to the shared singleton.
    override private init() {
        super.init()
        decoder.dateDecodingStrategy = .deferredToDate
    }

    /// Requests the system to launch the companion watch workout.
    func startCompanionWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Share authorization with the iPhone workout manager to avoid overlapping requests.
        try await PhoneWorkoutManager.shared.ensureAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

        try await healthStore.startWatchApp(toHandle: configuration)
    }

    /// Registers the mirroring callback early in the iPhone app lifecycle.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Register early to receive Watch workouts during background launches.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.attachMirroredSession(session)
            }
        }

        // Registration is safe in background; PhoneWorkoutManager owns authorization UI.
    }

    /// Attaches the mirrored workout session so payloads can be received.
    private func attachMirroredSession(_ session: HKWorkoutSession) {
        // Retain the mirrored session to receive remote workout payloads.
        mirroredSession = session
        mirroredSession?.delegate = self
    }
}

extension WorkoutMirrorManager: HKWorkoutSessionDelegate {
    /// Decodes mirrored workout payloads received from Apple Watch.
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data])
    {
        // HealthKit may deliver several payloads in one callback after background suspension.
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
