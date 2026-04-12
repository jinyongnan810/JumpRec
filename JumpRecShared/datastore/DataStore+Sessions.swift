//
//  DataStore+Sessions.swift
//  JumpRec
//

import Foundation
import SwiftData

public extension MyDataStore {
    /// Removes short sessions that are usually created during local development and manual testing.
    /// This runs only in debug builds during store bootstrap so release users never lose history and
    /// developers start each launch from a cleaner dataset without having to clear the entire store.
    func removeDebugSessionsBelowMinimumJumpCountIfNeeded() {
        #if DEBUG
            let minimumJumpCount = 100
            let descriptor = FetchDescriptor<JumpSession>(
                predicate: #Predicate { session in
                    session.jumpCount < minimumJumpCount
                }
            )
            let sessionsToDelete = (try? modelContext.fetch(descriptor)) ?? []

            guard !sessionsToDelete.isEmpty else { return }

            for session in sessionsToDelete {
                modelContext.delete(session)
            }

            saveContextIfNeeded()
            print("[DataStore] Debug cleanup removed \(sessionsToDelete.count) sessions with fewer than \(minimumJumpCount) jumps")
        #endif
    }

    /// Inserts a session and any derived rate samples into the model context.
    func addSession(session: JumpSession, rateSamples: [SessionRateSample] = []) {
        modelContext.insert(session)
        attach(rateSamples, to: session)
        let updatedRecordKinds = upsertPersonalRecords(for: session)
        if !updatedRecordKinds.isEmpty {
            markUnseenPersonalRecordUpdates(updatedRecordKinds)
        }
        saveContextIfNeeded()

        print("inserted session and rate samples")
        print("session: \(session)")
        print("samples: \(rateSamples.count)")
    }

    /// Creates a finalized session record and persists it with normalized rate samples.
    @discardableResult
    func saveCompletedSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int? = nil,
        peakHeartRate: Int? = nil
    ) -> JumpSession {
        let breakMetrics = SessionMetricsCalculator.breakMetrics(from: jumpOffsets)
        let session = JumpSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpCount,
            peakRate: 0,
            caloriesBurned: caloriesBurned,
            smallBreaksCount: breakMetrics.small,
            longBreaksCount: breakMetrics.long,
            longestStreak: breakMetrics.longestStreak,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRate
        )

        let rateSamples = SessionMetricsCalculator.makeRateSamples(
            for: session,
            jumpOffsets: jumpOffsets,
            durationSeconds: session.durationSeconds
        )

        session.peakRate = SessionMetricsCalculator.peakRate(from: rateSamples)
        session.averageRate = SessionMetricsCalculator.averageRate(
            jumpCount: session.jumpCount,
            durationSeconds: session.durationSeconds
        )

        addSession(session: session, rateSamples: rateSamples)
        Task { @MainActor [weak self] in
            guard let self else { return }
            await SessionAICommentGenerator.generateIfNeeded(for: session, in: modelContext)
        }
        return session
    }

    @discardableResult
    func generateAICommentIfNeeded(for session: JumpSession) async -> String? {
        await SessionAICommentGenerator.generateIfNeeded(for: session, in: modelContext)
    }

    /// Links rate samples to their owning session before insertion.
    private func attach(_ rateSamples: [SessionRateSample], to session: JumpSession) {
        for sample in rateSamples {
            sample.session = session
            if session.rateSamples == nil {
                session.rateSamples = []
            }
            session.rateSamples?.append(sample)
            modelContext.insert(sample)
        }
    }
}
