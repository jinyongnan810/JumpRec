//
//  DataStore.swift
//  ListIt
//
//  Created by Yuunan kin on 2025/09/06.
//
import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: ModelContainer

extension ModelContainer {
    /// Creates a shared ModelContainer with CloudKit sync enabled
    /// The container uses an App Group to share data between the main app and watchOS app
    /// - Returns: Configured ModelContainer with CloudKit automatic sync
    /// - Throws: Error if container creation fails
    static func createContainer() throws -> ModelContainer {
        // Define the data models that will be stored
        let schema = Schema([
            JumpSession.self,
            PersonalRecord.self,
            SessionRateSample.self,
        ])

        // Configure persistent storage with App Group and CloudKit
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false, // Persist to disk
            allowsSave: true,
            groupContainer: .identifier("group.com.kinn.JumpRec"), // Shared container for app extensions
            cloudKitDatabase: .automatic // Enable CloudKit sync across devices
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}

/// Singleton data store managing SwiftData persistence for the app
/// Provides a centralized access point for all data operations with automatic CloudKit sync
/// Must be accessed from the main actor since it manages UI-bound data
@MainActor
@Observable
public class MyDataStore {
    /// Shared singleton instance
    public static let shared = MyDataStore()

    /// The SwiftData model container managing persistent storage
    public let modelContainer: ModelContainer

    /// Main context for performing data operations
    public let modelContext: ModelContext

    private init() {
        do {
            // Initialize the shared container with CloudKit enabled
            modelContainer = try ModelContainer.createContainer()
            modelContext = modelContainer.mainContext

            // Enable automatic saving when changes are made
            // This works in conjunction with CloudKit to sync changes across devices
            modelContext.autosaveEnabled = true
            backfillPersonalRecordsIfNeeded()

            print("container and context initialized")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Save

    /// Manually saves the model context
    /// Note: This is currently not used since autosaveEnabled is true
    /// Kept for potential future use cases requiring explicit save control
    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    public func addSession(session: JumpSession, rateSamples: [SessionRateSample] = []) {
        modelContext.insert(session)
        for sample in rateSamples {
            sample.session = session
            if session.rateSamples == nil {
                session.rateSamples = []
            }
            session.rateSamples?.append(sample)
            modelContext.insert(sample)
        }
        upsertPersonalRecords(for: session)
        do {
            try modelContext.save()
            print("inserted session and rate samples")
            print("session: \(session)")
            print("samples: \(rateSamples.count)")
        } catch {
            print("failed to save")
        }
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

    private func upsertPersonalRecords(for session: JumpSession) {
        for candidate in personalRecordCandidates(for: session) {
            let kindRawValue = candidate.kind.rawValue
            let descriptor = FetchDescriptor<PersonalRecord>(
                predicate: #Predicate { record in
                    record.kindRawValue == kindRawValue
                }
            )

            let existingRecord = try? modelContext.fetch(descriptor).first
            let existingMetricValue = existingRecord?.metricValue
            guard existingRecord == nil || existingMetricValue == nil || candidate.kind.comparison.isBetter(
                newValue: candidate.metricValue,
                than: existingMetricValue ?? candidate.metricValue
            ) else {
                continue
            }

            if let existingRecord {
                existingRecord.metricValue = candidate.metricValue
                existingRecord.displayValue = candidate.displayValue
                existingRecord.achievedAt = candidate.achievedAt
            } else {
                modelContext.insert(
                    PersonalRecord(
                        kind: candidate.kind,
                        metricValue: candidate.metricValue,
                        displayValue: candidate.displayValue,
                        achievedAt: candidate.achievedAt
                    )
                )
            }
        }
    }

    private func personalRecordCandidates(for session: JumpSession) -> [PersonalRecordCandidate] {
        var candidates: [PersonalRecordCandidate] = [
            PersonalRecordCandidate(
                kind: .highestJumpCount,
                metricValue: Double(session.jumpCount),
                displayValue: String(
                    format: String(localized: "%@ jumps"),
                    session.jumpCount.formatted()
                ),
                achievedAt: session.startedAt
            ),
            PersonalRecordCandidate(
                kind: .longestSession,
                metricValue: Double(session.durationSeconds),
                displayValue: formattedDuration(seconds: session.durationSeconds),
                achievedAt: session.startedAt
            ),
            PersonalRecordCandidate(
                kind: .mostCalories,
                metricValue: session.caloriesBurned,
                displayValue: "\(Int(session.caloriesBurned.rounded())) \(String(localized: "cal"))",
                achievedAt: session.startedAt
            ),
        ]

        if let peakRate = session.peakRate {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .bestJumpRate,
                    metricValue: peakRate,
                    displayValue: localizedRateText(Int(peakRate.rounded())),
                    achievedAt: session.startedAt
                )
            )
        }

        return candidates
    }

    private func formattedDuration(seconds: Int) -> String {
        let minutes = seconds / 60
        let remainingSeconds = seconds % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }

    private func backfillPersonalRecordsIfNeeded() {
        let recordDescriptor = FetchDescriptor<PersonalRecord>()
        let existingRecords = (try? modelContext.fetch(recordDescriptor)) ?? []
        guard existingRecords.isEmpty else { return }

        let sessionDescriptor = FetchDescriptor<JumpSession>()
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        guard !sessions.isEmpty else { return }

        for session in sessions {
            upsertPersonalRecords(for: session)
        }

        save()
    }
}

private struct PersonalRecordCandidate {
    let kind: PersonalRecordKind
    let metricValue: Double
    let displayValue: String
    let achievedAt: Date
}
