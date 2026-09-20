//
//  JumpRecAppIntentsTests.swift
//  JumpRecTests
//

import AppIntents
import Foundation
@testable import JumpRec
import SwiftData
import Testing

@Suite(.serialized)
struct JumpRecAppIntentsTests {
    // MARK: - Entity Conversion Tests

    /// Tests conversion from SwiftData `JumpSession` to `JumpSessionEntity`.
    @Test func testJumpSessionEntityConversion() throws {
        let session = JumpSession(
            startedAt: Date(timeIntervalSince1970: 1_700_000_000),
            endedAt: Date(timeIntervalSince1970: 1_700_000_600),
            jumpCount: 1250,
            peakRate: 185.0,
            averageRate: 125.0,
            caloriesBurned: 142.5,
            smallBreaksCount: 2,
            longBreaksCount: 0,
            longestStreak: 450
        )

        let entity = JumpSessionEntity(from: session)

        #expect(entity.id == session.id)
        #expect(entity.startedAt == session.startedAt)
        #expect(entity.durationSeconds == session.durationSeconds)
        #expect(entity.jumpCount == 1250)
        #expect(entity.caloriesBurned == 142.5)
        #expect(entity.peakRate == 185.0)
        #expect(entity.averageRate == 125.0)
        #expect(entity.longestStreak == 450)
        #expect(entity.displayRepresentation.title != "")
    }

    /// Tests conversion from SwiftData `PersonalRecord` to `PersonalRecordEntity`.
    @Test func testPersonalRecordEntityConversion() throws {
        let record = PersonalRecord(
            kind: .highestJumpCount,
            metricValue: 2000,
            displayValue: "2,000",
            achievedAt: Date()
        )

        let entity = PersonalRecordEntity(from: record)

        #expect(entity.id == PersonalRecordKind.highestJumpCount.rawValue)
        #expect(entity.title == record.title)
        #expect(entity.displayValue == "2,000")
        #expect(entity.achievedAt == record.achievedAt)
        #expect(entity.displayRepresentation.title != "")
    }

    // MARK: - App Intent Execution Tests

    /// Tests `GetLatestWorkoutIntent` returns the most recent session with dialog.
    @MainActor
    @Test func testGetLatestWorkoutIntent() async throws {
        let context = MyDataStore.shared.modelContainer.mainContext
        let dummySession = JumpSession(
            startedAt: Date().addingTimeInterval(3600), // Far in future to be guaranteed latest
            endedAt: Date().addingTimeInterval(4200),
            jumpCount: 999,
            peakRate: 150,
            averageRate: 100,
            caloriesBurned: 88,
            longestStreak: 200
        )
        context.insert(dummySession)
        try context.save()

        let intent = GetLatestWorkoutIntent()
        let result = try await intent.perform()
        let wrappedEntity = try #require(result.value)
        let latestEntity = try #require(wrappedEntity)

        #expect(latestEntity.id == dummySession.id)
        #expect(latestEntity.jumpCount == 999)

        // Cleanup
        context.delete(dummySession)
        try context.save()
    }

    /// Tests `GetTodayJumpStatsIntent` aggregates today's jumps correctly.
    @MainActor
    @Test func testGetTodayJumpStatsIntent() async throws {
        let context = MyDataStore.shared.modelContainer.mainContext
        let session = JumpSession(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(300),
            jumpCount: 350,
            peakRate: 140,
            averageRate: 70,
            caloriesBurned: 40
        )
        context.insert(session)
        try context.save()

        let intent = GetTodayJumpStatsIntent()
        let result = try await intent.perform()
        let totalJumps = try #require(result.value)

        #expect(totalJumps >= 350)

        // Cleanup
        context.delete(session)
        try context.save()
    }

    /// Tests `SearchWorkoutsIntent` searches and matches sessions.
    @MainActor
    @Test func testSearchWorkoutsIntent() async throws {
        let context = MyDataStore.shared.modelContainer.mainContext
        let uniqueCount = 8871
        let session = JumpSession(
            startedAt: Date(),
            endedAt: Date().addingTimeInterval(120),
            jumpCount: uniqueCount,
            peakRate: 120,
            caloriesBurned: 20
        )
        context.insert(session)
        try context.save()

        let intent = SearchWorkoutsIntent(query: "\(uniqueCount)")
        let result = try await intent.perform()
        let matching = try #require(result.value)

        #expect(!matching.isEmpty)
        #expect(matching.contains(where: { $0.id == session.id }))

        // Cleanup
        context.delete(session)
        try context.save()
    }

    /// Tests `WorkoutStatsEntity` representation for all-time and yearly stats.
    @Test func testWorkoutStatsEntity() throws {
        let allTime = WorkoutStatsEntity(totalJumps: 5000, sessionCount: 10, year: nil, caloriesBurned: 600)
        #expect(allTime.totalJumps == 5000)
        #expect(allTime.sessionCount == 10)
        #expect(allTime.year == nil)
        #expect(allTime.displayRepresentation.title != "")

        let yearly = WorkoutStatsEntity(totalJumps: 2500, sessionCount: 5, year: 2025, caloriesBurned: 300)
        #expect(yearly.totalJumps == 2500)
        #expect(yearly.sessionCount == 5)
        #expect(yearly.year == 2025)
        #expect(yearly.displayRepresentation.title != "")
    }

    /// Tests `GetWorkoutStatsIntent` for both all-time and specific year queries.
    @MainActor
    @Test func testGetWorkoutStatsIntentAllTimeAndYearly() async throws {
        let context = MyDataStore.shared.modelContainer.mainContext
        let calendar = Calendar.current

        // Date in 2024
        var comps2024 = DateComponents()
        comps2024.year = 2024
        comps2024.month = 6
        comps2024.day = 15
        comps2024.hour = 10
        let date2024 = try #require(calendar.date(from: comps2024))

        // Date in 2025
        var comps2025 = DateComponents()
        comps2025.year = 2025
        comps2025.month = 3
        comps2025.day = 20
        comps2025.hour = 14
        let date2025 = try #require(calendar.date(from: comps2025))

        let session2024 = JumpSession(
            startedAt: date2024,
            endedAt: date2024.addingTimeInterval(300),
            jumpCount: 400,
            peakRate: 150,
            caloriesBurned: 45
        )
        let session2025 = JumpSession(
            startedAt: date2025,
            endedAt: date2025.addingTimeInterval(600),
            jumpCount: 800,
            peakRate: 160,
            caloriesBurned: 90
        )

        context.insert(session2024)
        context.insert(session2025)
        try context.save()

        // 1. Query for 2024 specifically
        let intent2024 = GetWorkoutStatsIntent(year: 2024)
        let result2024 = try await intent2024.perform()
        let stats2024 = try #require(result2024.value)
        #expect(stats2024.totalJumps >= 400)
        #expect(stats2024.sessionCount >= 1)
        #expect(stats2024.year == 2024)

        // 2. Query for all-time
        let intentAllTime = GetWorkoutStatsIntent(year: nil)
        let resultAllTime = try await intentAllTime.perform()
        let statsAllTime = try #require(resultAllTime.value)
        #expect(statsAllTime.totalJumps >= 1200)
        #expect(statsAllTime.sessionCount >= 2)
        #expect(statsAllTime.year == nil)

        // Cleanup
        context.delete(session2024)
        context.delete(session2025)
        try context.save()
    }

    // MARK: - FoundationModels AI Tools Tests

    /// Tests FoundationModels AI tools on supported iOS 26+ environments.
    @MainActor
    @Test func testFoundationModelsAITools() async throws {
        #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let context = MyDataStore.shared.modelContainer.mainContext
                let testSession = JumpSession(
                    startedAt: Date(),
                    endedAt: Date().addingTimeInterval(600),
                    jumpCount: 777,
                    peakRate: 160,
                    caloriesBurned: 80
                )
                context.insert(testSession)
                try context.save()

                let recentTool = GetRecentWorkoutsAITool()
                let recentOutput = try await recentTool.call(arguments: GetRecentWorkoutsAITool.Arguments(count: 3))
                #expect(!recentOutput.isEmpty)

                let summaryTool = GetWorkoutSummaryStatsAITool()
                let summaryOutput = try await summaryTool.call(arguments: GetWorkoutSummaryStatsAITool.Arguments(days: 7))
                #expect(summaryOutput.contains("Summary for the past 7 days"))

                let aggTool = GetAggregatedWorkoutStatsAITool()
                let aggOutput = try await aggTool.call(arguments: GetAggregatedWorkoutStatsAITool.Arguments(year: nil))
                #expect(aggOutput.contains("All-time Statistics"))

                // Cleanup
                context.delete(testSession)
                try context.save()
            }
        #endif
    }
}
