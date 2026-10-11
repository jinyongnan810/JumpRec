//
//  DataStore+Sessions.swift
//  JumpRec
//

import Foundation
import SwiftData

public extension MyDataStore {
    /// Fetches scalar summaries for [January 1, next January 1), or all history when year is omitted.
    func sessionsForStatistics(year: Int?) throws -> [JumpSession] {
        var descriptor = FetchDescriptor<JumpSession>()
        if let year {
            let calendar = Calendar.current
            guard let start = calendar.date(from: DateComponents(year: year, month: 1, day: 1)),
                  let end = calendar.date(byAdding: .year, value: 1, to: start) else { return [] }
            descriptor.predicate = #Predicate { $0.startedAt >= start && $0.startedAt < end }
        }
        return try modelContext.fetch(descriptor)
    }

    /// Deletes short development sessions during debug-only store startup.
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

    /// Counts workouts with at least 100 jumps toward the free quota.
    func qualifiedSessionsCount() -> Int {
        let minimumJumpCount = JumpRecSettings.minimumJumpsForQuotaQualification
        let descriptor = FetchDescriptor<JumpSession>(
            predicate: #Predicate { session in
                session.jumpCount >= minimumJumpCount
            }
        )
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Allows workouts with an unlimited license or fewer than 100 qualifying sessions.
    func canStartNewWorkout(isLicenseUnlocked: Bool) -> Bool {
        if isLicenseUnlocked {
            return true
        }
        return qualifiedSessionsCount() < JumpRecSettings.freeWorkoutQuota
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

    /// Stores chart samples in a separate child row for lazy loading.
    private func attachRateSeries(_ rateSamples: [RateSamplePoint], to session: JumpSession) {
        guard !rateSamples.isEmpty else { return }

        session.replaceRateSamples(with: rateSamples)

        if let rateSeries = session.rateSeries {
            modelContext.insert(rateSeries)
        }
    }
}
