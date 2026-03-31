//
//  DataStore+PersonalRecords.swift
//  JumpRec
//

import Foundation
import SwiftData

extension MyDataStore {
    /// Minimum values a session must reach before it can establish a personal record.
    /// This avoids surfacing trivial early-session numbers as "records" when the user
    /// has not yet completed a meaningful workout.
    private enum PersonalRecordThreshold {
        static let highestJumpCount = 200
        static let longestJumpStreak = 100
        static let longestSessionDurationSeconds = 60
        static let mostCalories = 20.0
        static let steadyRhythmSampleCount = 12
        static let averageJumpRateDurationSeconds = 60
        static let sneakyBurnDurationSeconds = 60
    }

    @discardableResult
    func upsertPersonalRecords(for session: JumpSession) -> [PersonalRecordKind] {
        var updatedKinds: [PersonalRecordKind] = []
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

            if !updatedKinds.contains(candidate.kind) {
                updatedKinds.append(candidate.kind)
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
        return updatedKinds
    }

    /// Removes every cached personal record row from the local store.
    /// This is intentionally scoped to the derived record cache only, so clearing the sheet does not
    /// destroy the underlying session history that future record calculations still depend on.
    func clearAllPersonalRecords() {
        let descriptor = FetchDescriptor<PersonalRecord>()
        let existingRecords = (try? modelContext.fetch(descriptor)) ?? []

        guard !existingRecords.isEmpty else {
            // Keeping the unseen state in sync avoids stale badges if the user clears records from an already-empty sheet.
            clearUnseenPersonalRecordUpdates()
            return
        }

        for record in existingRecords {
            modelContext.delete(record)
        }

        // Clearing the records also clears any "new record" badge state because there is nothing left to acknowledge.
        clearUnseenPersonalRecordUpdates()
        saveContextIfNeeded()
    }

    func backfillPersonalRecordsIfNeeded() {
        let recordDescriptor = FetchDescriptor<PersonalRecord>()
        let existingRecords = (try? modelContext.fetch(recordDescriptor)) ?? []
        let existingKinds = Set(
            existingRecords.compactMap { record in
                record.kindRawValue.flatMap(PersonalRecordKind.init(rawValue:))
            }
        )
        guard existingKinds.count < PersonalRecordKind.allCases.count else { return }

        let sessionDescriptor = FetchDescriptor<JumpSession>()
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        guard !sessions.isEmpty else { return }

        // Reprocessing all historical sessions keeps previously shipped record kinds intact while
        // allowing newly introduced kinds to be derived for existing users during app upgrade.
        for session in sessions {
            upsertPersonalRecords(for: session)
        }

        saveContextIfNeeded()
    }

    private func personalRecordCandidates(for session: JumpSession) -> [PersonalRecordCandidate] {
        var candidates: [PersonalRecordCandidate] = []
        // Session rate samples are persisted in chronological order when the session is saved,
        // so record calculations can consume them directly without re-sorting on every update.
        let rateSamples = session.rateSamples ?? []

        // Each category has a minimum qualification threshold so personal records reflect
        // a meaningful workout milestone instead of the first small session in history.
        if session.jumpCount > PersonalRecordThreshold.highestJumpCount {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .highestJumpCount,
                    metricValue: Double(session.jumpCount),
                    displayValue: String(
                        format: String(localized: "%@ jumps"),
                        session.jumpCount.formatted()
                    ),
                    achievedAt: session.startedAt
                )
            )
        }

        if session.longestStreak > PersonalRecordThreshold.longestJumpStreak {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .longestJumpStreak,
                    metricValue: Double(session.longestStreak),
                    displayValue: String(
                        format: String(localized: "%@ jumps"),
                        session.longestStreak.formatted()
                    ),
                    achievedAt: session.startedAt
                )
            )
        }

        if session.durationSeconds > PersonalRecordThreshold.longestSessionDurationSeconds {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .longestSession,
                    metricValue: Double(session.durationSeconds),
                    displayValue: formattedDuration(seconds: session.durationSeconds),
                    achievedAt: session.startedAt
                )
            )
        }

        if session.caloriesBurned > PersonalRecordThreshold.mostCalories {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .mostCalories,
                    metricValue: session.caloriesBurned,
                    displayValue: "\(Int(session.caloriesBurned.rounded())) \(String(localized: "cal"))",
                    achievedAt: session.startedAt
                )
            )
        }

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

        // These playful records rely on persisted rate samples, so they are only eligible once
        // the session is long enough to provide meaningful pacing data.
        if
            rateSamples.count >= PersonalRecordThreshold.steadyRhythmSampleCount,
            let rhythmScore = SessionMetricsCalculator.rhythmConsistencyScore(from: rateSamples)
        {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .steadyRhythm,
                    metricValue: rhythmScore,
                    displayValue: localizedPercentText(rhythmScore),
                    achievedAt: session.startedAt
                )
            )
        }

        if
            session.durationSeconds >= PersonalRecordThreshold.averageJumpRateDurationSeconds,
            let averageRate = session.averageRate
        {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .bestAverageJumpRate,
                    metricValue: averageRate,
                    displayValue: localizedRateText(Int(averageRate.rounded())),
                    achievedAt: session.startedAt
                )
            )
        }

        if
            session.durationSeconds >= PersonalRecordThreshold.sneakyBurnDurationSeconds,
            session.caloriesBurned > PersonalRecordThreshold.mostCalories,
            let caloriesPerMinute = SessionMetricsCalculator.caloriesPerMinute(
                caloriesBurned: session.caloriesBurned,
                durationSeconds: session.durationSeconds
            )
        {
            candidates.append(
                PersonalRecordCandidate(
                    kind: .sneakyBurn,
                    metricValue: caloriesPerMinute,
                    displayValue: localizedCaloriesPerMinuteText(caloriesPerMinute),
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
}

private struct PersonalRecordCandidate {
    let kind: PersonalRecordKind
    let metricValue: Double
    let displayValue: String
    let achievedAt: Date
}
