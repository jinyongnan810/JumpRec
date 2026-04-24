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

    /// Inserts a session and its encoded rate series into the model context.
    func addSession(session: JumpSession, rateSamples: [RateSamplePoint] = []) {
        modelContext.insert(session)
        attachRateSeries(rateSamples, to: session)
        let updatedRecordKinds = upsertPersonalRecords(for: session)
        if !updatedRecordKinds.isEmpty {
            markUnseenPersonalRecordUpdates(updatedRecordKinds)
        }
        saveContextIfNeeded()

        print("inserted session and encoded rate series")
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

    /// Creates the single child blob row for a session's rate samples.
    ///
    /// The list screen only needs the scalar fields on `JumpSession`, so storing rate points in this
    /// separate one-to-one object prevents normal history fetches from materializing chart data. The
    /// detail screen still has full fidelity by decoding `JumpSession.decodedRateSamples` on demand.
    private func attachRateSeries(_ rateSamples: [RateSamplePoint], to session: JumpSession) {
        guard !rateSamples.isEmpty else { return }

        session.replaceRateSamples(with: rateSamples)

        if let rateSeries = session.rateSeries {
            modelContext.insert(rateSeries)
        }
    }
}
