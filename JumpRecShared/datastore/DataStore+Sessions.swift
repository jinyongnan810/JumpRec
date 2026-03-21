//
//  DataStore+Sessions.swift
//  JumpRec
//

import Foundation
import SwiftData

extension MyDataStore {
    /// Inserts a session and any derived rate samples into the model context.
    public func addSession(session: JumpSession, rateSamples: [SessionRateSample] = []) {
        modelContext.insert(session)
        attach(rateSamples, to: session)
        upsertPersonalRecords(for: session)
        saveContextIfNeeded()

        print("inserted session and rate samples")
        print("session: \(session)")
        print("samples: \(rateSamples.count)")
    }

    /// Creates a finalized session record and persists it with normalized rate samples.
    @discardableResult
    public func saveCompletedSession(
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
    public func generateAICommentIfNeeded(for session: JumpSession) async -> String? {
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
