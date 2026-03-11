//
//  WorkoutMirrorManager.swift
//  JumpRec
//

import Foundation
import HealthKit
import JumpRecShared

@MainActor
final class WorkoutMirrorManager: NSObject {
    static let shared = WorkoutMirrorManager()

    var onPayloadReceived: ((MirroredWorkoutPayload) -> Void)?
    var onMirroredSessionEnded: (() -> Void)?

    private let healthStore = HKHealthStore()
    private let decoder = JSONDecoder()
    private var mirroredSession: HKWorkoutSession?

    override private init() {
        super.init()
        decoder.dateDecodingStrategy = .deferredToDate
    }

    func activate() {
        guard HKHealthStore.isHealthDataAvailable() else { return }

        healthStore.workoutSessionMirroringStartHandler = { [weak self] session in
            Task { @MainActor in
                self?.attachMirroredSession(session)
            }
        }

        requestAuthorization()
    }

    private func requestAuthorization() {
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
        mirroredSession = session
        mirroredSession?.delegate = self
    }
}

extension WorkoutMirrorManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_: HKWorkoutSession,
                                    didReceiveDataFromRemoteWorkoutSession data: [Data])
    {
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
