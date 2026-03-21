//
//  DataStore+PersonalRecords.swift
//  JumpRec
//

import Foundation
import SwiftData

extension MyDataStore {
    func upsertPersonalRecords(for session: JumpSession) {
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

    func backfillPersonalRecordsIfNeeded() {
        let recordDescriptor = FetchDescriptor<PersonalRecord>()
        let existingRecords = (try? modelContext.fetch(recordDescriptor)) ?? []
        guard existingRecords.isEmpty else { return }

        let sessionDescriptor = FetchDescriptor<JumpSession>()
        let sessions = (try? modelContext.fetch(sessionDescriptor)) ?? []
        guard !sessions.isEmpty else { return }

        for session in sessions {
            upsertPersonalRecords(for: session)
        }

        saveContextIfNeeded()
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
                kind: .longestJumpStreak,
                metricValue: Double(session.longestStreak),
                displayValue: String(
                    format: String(localized: "%@ jumps"),
                    session.longestStreak.formatted()
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
}

private struct PersonalRecordCandidate {
    let kind: PersonalRecordKind
    let metricValue: Double
    let displayValue: String
    let achievedAt: Date
}
