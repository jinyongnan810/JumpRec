//
//  WorkoutMirrorManager.swift
//  JumpRec
//

import Foundation
import HealthKit

@MainActor
final class WorkoutMirrorManager: NSObject {
    static let shared = WorkoutMirrorManager()

    var onPayloadReceived: ((MirroredWorkoutPayload) -> Void)?
    var onMirroredSessionEnded: (() -> Void)?

    // The iPhone must own an HKHealthStore to participate in HealthKit workout mirroring.
    // This is separate from WatchConnectivity:
    // - WCSession is for general app/watch messaging.
    // - HKWorkoutSession mirroring is for an active HealthKit workout and lets the system
    //   wake the companion iPhone app, attach a mirrored session, and deliver workout data.
    private let healthStore = HKHealthStore()
    private let decoder = JSONDecoder()
    private var mirroredSession: HKWorkoutSession?

    override private init() {
        super.init()
        decoder.dateDecodingStrategy = .deferredToDate
    }

    func startCompanionWorkout() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .jumpRope
        configuration.locationType = .outdoor

        try await healthStore.startWatchApp(toHandle: configuration)
    }

    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        // Register this as early as possible so the iPhone can receive a mirrored workout
        // session started from Apple Watch, even if the iOS app is launched in background.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }

        requestAuthorization()
    }

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

    private func attachMirroredSession(_ session: HKWorkoutSession) {
        // Keep a reference to the mirrored session so the iPhone can receive payloads sent with
        // sendToRemoteWorkoutSession(data:) from the watch's primary HKWorkoutSession.
        mirroredSession = session
        mirroredSession?.delegate = self
    }
}

extension WorkoutMirrorManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data])
    {
        // HealthKit may batch multiple payloads before delivering them to iPhone,
        // especially when the iOS app was suspended in background.
        for payloadData in data {
            do {
                let payload = try decoder.decode(MirroredWorkoutPayload.self, from: payloadData)
                Task { @MainActor in
                    self.onPayloadReceived?(payload)
                }
            } catch {
                print("[WorkoutMirrorManager] Failed to decode mirrored payload: \(error)")
            }
        }
    }

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

    nonisolated func workoutSession(_: HKWorkoutSession, didFailWithError error: Error) {
        print("[WorkoutMirrorManager] Mirrored session error: \(error)")
    }
}
