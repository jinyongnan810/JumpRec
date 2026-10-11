import Foundation
@testable import JumpRec
import SwiftData
import Testing

@MainActor
struct SessionBackupTests {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([JumpSession.self, SessionRateSeries.self, PersonalRecord.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: configuration)
    }

    @Test func roundTripPreservesSessionValuesAndSkipsRepeatedImports() throws {
        let source = try makeContainer()
        let startedAt = Date(timeIntervalSince1970: 1_700_000_000.125)
        let session = JumpSession(
            startedAt: startedAt, endedAt: startedAt.addingTimeInterval(60), jumpCount: 140,
            peakRate: 160, averageRate: 140, caloriesBurned: 12.5,
            smallBreaksCount: 2, longBreaksCount: 1, longestStreak: 90,
            averageHeartRate: 130, peakHeartRate: 155, aiComment: "Good pace"
        )
        session.peakRate = nil
        session.replaceRateSamples(with: [RateSamplePoint(secondOffset: 5, rate: 140)])
        source.mainContext.insert(session)
        try source.mainContext.save()
        let original = try SessionBackup.capture(from: source)
        let backup = try SessionBackup.decode(original.encoded())
        let destination = try makeContainer()
        let first = try backup.restore(into: destination)
        let second = try backup.restore(into: destination)
        #expect(first.imported == 1 && first.skipped == 0)
        #expect(second.imported == 0 && second.skipped == 1)
        let restored = try SessionBackup.capture(from: destination)
        // Compare the complete DTO, including optional values and the raw chart payload.
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(restored.sessions) == encoder.encode(original.sessions))
    }

    @Test func importKeepsBetterPersonalRecords() throws {
        let source = try makeContainer()
        source.mainContext.insert(PersonalRecord(kind: .highestJumpCount, metricValue: 300, displayValue: "300", achievedAt: Date()))
        try source.mainContext.save()
        let destination = try makeContainer()
        destination.mainContext.insert(PersonalRecord(kind: .highestJumpCount, metricValue: 500, displayValue: "500", achievedAt: Date()))
        try destination.mainContext.save()
        let backup = try SessionBackup.capture(from: source)
        _ = try backup.restore(into: destination)
        let records = try ModelContext(destination).fetch(FetchDescriptor<PersonalRecord>())
        #expect(records.count == 1)
        #expect(records.first?.metricValue == 500)
    }

    @Test func invalidBackupDoesNotInsertSessions() throws {
        let source = try makeContainer()
        source.mainContext.insert(JumpSession(startedAt: Date(), endedAt: Date(), jumpCount: -1, peakRate: 0, caloriesBurned: 0))
        try source.mainContext.save()
        let backup = try SessionBackup.capture(from: source)
        let destination = try makeContainer()
        #expect(throws: SessionBackup.BackupError.self) { try backup.restore(into: destination) }
        #expect(try destination.mainContext.fetchCount(FetchDescriptor<JumpSession>()) == 0)
    }

    @Test func rejectsUnknownVersionAndDuplicateSessionIDs() throws {
        let source = try makeContainer()
        source.mainContext.insert(JumpSession(startedAt: Date(), endedAt: Date(), jumpCount: 10, peakRate: 10, caloriesBurned: 1))
        try source.mainContext.save()
        let backup = try SessionBackup.capture(from: source)
        let unsupported = SessionBackup(format: "JumpRec", version: 2, exportedAt: Date(), sessions: backup.sessions, personalRecords: [])
        #expect(throws: SessionBackup.BackupError.self) { try SessionBackup.decode(unsupported.encoded()) }
        let duplicate = SessionBackup(format: "JumpRec", version: 1, exportedAt: Date(), sessions: backup.sessions + backup.sessions, personalRecords: [])
        #expect(throws: SessionBackup.BackupError.self) { try duplicate.restore(into: makeContainer()) }
    }
}
