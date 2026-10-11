import Foundation
import SwiftData

/// Portable model values; CloudKit record IDs and local store metadata are excluded.
nonisolated struct SessionBackup: Codable, Sendable {
    let format: String
    let version: Int
    let exportedAt: Date
    let sessions: [Session]
    let personalRecords: [Record]

    struct Session: Codable, Sendable {
        let id: UUID
        let startedAt: Date
        let endedAt: Date
        let jumpCount: Int
        let peakRate: Double?
        let averageRate: Double?
        let caloriesBurned: Double
        let durationSeconds: Int
        let smallBreaksCount: Int
        let longBreaksCount: Int
        let longestStreak: Int
        let averageHeartRate: Int?
        let peakHeartRate: Int?
        let aiComment: String?
        let rateSeries: Series?

        @MainActor
        init(_ session: JumpSession) {
            id = session.id
            startedAt = session.startedAt
            endedAt = session.endedAt
            jumpCount = session.jumpCount
            peakRate = session.peakRate
            averageRate = session.averageRate
            caloriesBurned = session.caloriesBurned
            durationSeconds = session.durationSeconds
            smallBreaksCount = session.smallBreaksCount
            longBreaksCount = session.longBreaksCount
            longestStreak = session.longestStreak
            averageHeartRate = session.averageHeartRate
            peakHeartRate = session.peakHeartRate
            aiComment = session.aiComment
            rateSeries = session.rateSeries.map(Series.init)
        }

        @MainActor
        func makeModel() -> JumpSession {
            let session = JumpSession(
                startedAt: startedAt, endedAt: startedAt, jumpCount: jumpCount,
                peakRate: peakRate ?? 0, caloriesBurned: caloriesBurned
            )
            session.id = id
            session.startedAt = startedAt
            session.endedAt = endedAt
            session.jumpCount = jumpCount
            session.peakRate = peakRate
            session.averageRate = averageRate
            session.caloriesBurned = caloriesBurned
            session.durationSeconds = durationSeconds
            session.smallBreaksCount = smallBreaksCount
            session.longBreaksCount = longBreaksCount
            session.longestStreak = longestStreak
            session.averageHeartRate = averageHeartRate
            session.peakHeartRate = peakHeartRate
            session.aiComment = aiComment
            if let rateSeries {
                session.rateSeries = SessionRateSeries(
                    session: session, payload: rateSeries.payload,
                    sampleCount: rateSeries.sampleCount, version: rateSeries.version
                )
            }
            return session
        }
    }

    struct Series: Codable, Sendable {
        let payload: Data?
        let sampleCount: Int
        let version: Int

        @MainActor
        init(_ series: SessionRateSeries) {
            payload = series.payload
            sampleCount = series.sampleCount
            version = series.version
        }
    }

    struct Record: Codable, Sendable {
        let kindRawValue: String?
        let metricValue: Double?
        let displayValue: String?
        let achievedAt: Date?

        @MainActor
        init(_ record: PersonalRecord) {
            kindRawValue = record.kindRawValue
            metricValue = record.metricValue
            displayValue = record.displayValue
            achievedAt = record.achievedAt
        }

        @MainActor
        func apply(to record: PersonalRecord) {
            record.kindRawValue = kindRawValue
            record.metricValue = metricValue
            record.displayValue = displayValue
            record.achievedAt = achievedAt
        }
    }

    enum BackupError: Error {
        case unsupportedFormat
        case invalidData
    }

    @MainActor
    static func capture(from container: ModelContainer) throws -> SessionBackup {
        let context = ModelContext(container)
        return try SessionBackup(
            format: "JumpRec", version: 1, exportedAt: Date(),
            sessions: context.fetch(FetchDescriptor<JumpSession>(sortBy: [SortDescriptor(\.startedAt)])).map(Session.init),
            personalRecords: context.fetch(FetchDescriptor<PersonalRecord>()).map(Record.init)
        )
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> SessionBackup {
        let backup = try JSONDecoder().decode(SessionBackup.self, from: data)
        try backup.validate()
        return backup
    }

    func validate() throws {
        guard format == "JumpRec", version == 1 else { throw BackupError.unsupportedFormat }
        guard Set(sessions.map(\.id)).count == sessions.count else { throw BackupError.invalidData }
        for session in sessions {
            guard session.endedAt >= session.startedAt,
                  session.jumpCount >= 0, session.durationSeconds >= 0,
                  session.smallBreaksCount >= 0, session.longBreaksCount >= 0,
                  session.longestStreak >= 0, session.caloriesBurned >= 0,
                  session.peakRate.map({ $0 >= 0 }) ?? true,
                  session.averageRate.map({ $0 >= 0 }) ?? true,
                  session.averageHeartRate.map({ $0 >= 0 }) ?? true,
                  session.peakHeartRate.map({ $0 >= 0 }) ?? true
            else { throw BackupError.invalidData }
            if let series = session.rateSeries {
                guard series.version == 1, series.sampleCount >= 0 else { throw BackupError.invalidData }
                if let payload = series.payload {
                    let samples = try JSONDecoder().decode([RateSamplePoint].self, from: payload)
                    guard samples.count == series.sampleCount,
                          samples.allSatisfy({ $0.secondOffset >= 0 && $0.rate.isFinite && $0.rate >= 0 })
                    else { throw BackupError.invalidData }
                } else if series.sampleCount != 0 {
                    throw BackupError.invalidData
                }
            }
        }
        for record in personalRecords {
            guard let rawValue = record.kindRawValue,
                  PersonalRecordKind(rawValue: rawValue) != nil,
                  record.metricValue.map({ $0 >= 0 }) ?? true
            else { throw BackupError.invalidData }
        }
    }

    /// A separate context keeps failed imports from rolling back unrelated edits.
    @MainActor
    func restore(into container: ModelContainer) throws -> (imported: Int, skipped: Int) {
        try validate()
        let context = ModelContext(container)
        context.autosaveEnabled = false
        var existingIDs = try Set(context.fetch(FetchDescriptor<JumpSession>()).map(\.id))
        var records = try context.fetch(FetchDescriptor<PersonalRecord>())
        var imported = 0
        do {
            for session in sessions where existingIDs.insert(session.id).inserted {
                context.insert(session.makeModel())
                imported += 1
            }
            for snapshot in personalRecords {
                guard let rawValue = snapshot.kindRawValue,
                      let kind = PersonalRecordKind(rawValue: rawValue) else { continue }
                let matchingRecords = records.filter { $0.kindRawValue == rawValue }
                if matchingRecords.isEmpty {
                    let record = PersonalRecord(kind: kind, metricValue: 0, displayValue: "", achievedAt: exportedAt)
                    snapshot.apply(to: record)
                    context.insert(record)
                    records.append(record)
                } else if let value = snapshot.metricValue {
                    // A kind may have duplicate rows after CloudKit merges; never downgrade any row.
                    for record in matchingRecords where record.metricValue == nil || kind.comparison.isBetter(newValue: value, than: record.metricValue ?? value) {
                        snapshot.apply(to: record)
                    }
                }
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        return (imported, sessions.count - imported)
    }
}
