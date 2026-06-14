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

        // Reuse the iPhone workout manager's authorization task so launching the Watch app never
        // races a second HealthKit request against the authorization primed during app startup.
        try await PhoneWorkoutManager.shared.ensureAuthorization()

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

        try await healthStore.startWatchApp(toHandle: configuration)
    }

    /// Registers the mirroring callback early in the iPhone app lifecycle.
    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Register this as early as possible so the iPhone can receive a mirrored workout
        // session started from Apple Watch, even if the iOS app is launched in background.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor [weak self] in
                self?.attachMirroredSession(session)
            }
        }

        // PhoneWorkoutManager owns the combined iPhone authorization request. Registration itself
        // does not need to present UI and must remain safe when the app is launched in background.
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
