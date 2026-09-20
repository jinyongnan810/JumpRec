//
//  WorkoutStatsEntity.swift
//  JumpRec
//

import AppIntents
import Foundation
import SwiftData

/// An App Entity representing aggregated workout statistics (all-time or for a specific year) in JumpRec.
///
/// Enables Siri, Shortcuts, and Apple Intelligence to inspect aggregated workout metrics such as
/// total jumps, total session count, and calories burned for all time or a specific calendar year.
public struct WorkoutStatsEntity: AppEntity, Identifiable, Sendable {
    /// Localized display representation for the entity type in Shortcuts.
    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout Statistics"

    /// The default entity query used by the system to look up workout stats.
    public static var defaultQuery = WorkoutStatsQuery()

    /// Unique identifier: either the year string (e.g. "2026") or "all_time".
    public var id: String

    /// Total number of detected jumps in the period.
    @Property(title: "Total Jumps")
    public var totalJumps: Int

    /// Total number of completed workout sessions in the period.
    @Property(title: "Session Count")
    public var sessionCount: Int

    /// Specific calendar year if queried for a specific year, or nil for all-time.
    @Property(title: "Year")
    public var year: Int?

    /// Total estimated calories burned across the period.
    @Property(title: "Calories Burned")
    public var caloriesBurned: Int

    /// Formats the statistics for presentation in Siri dialogs and Shortcuts results.
    public var displayRepresentation: DisplayRepresentation {
        let label = year.map { "\($0) Stats" } ?? "All-Time Stats"
        let sessionLabel = sessionCount == 1 ? "1 workout" : "\(sessionCount) workouts"
        let subtitle = "\(sessionLabel) • \(caloriesBurned) kcal"

        return DisplayRepresentation(
            title: "\(label): \(totalJumps.formatted()) jumps",
            subtitle: LocalizedStringResource(stringLiteral: subtitle)
        )
    }

    /// Memberwise initializer for creating an aggregated statistics snapshot.
    public init(
        totalJumps: Int,
        sessionCount: Int,
        year: Int? = nil,
        caloriesBurned: Int = 0
    ) {
        id = year.map { String($0) } ?? "all_time"
        self.totalJumps = totalJumps
        self.sessionCount = sessionCount
        self.year = year
        self.caloriesBurned = caloriesBurned
    }
}

/// Query implementation allowing Shortcuts to resolve workout statistics entities.
public struct WorkoutStatsQuery: EntityQuery, Sendable {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [WorkoutStatsEntity] {
        let context = MyDataStore.shared.modelContainer.mainContext
        let calendar = Calendar.current
        let descriptor = FetchDescriptor<JumpSession>()
        let allSessions = (try? context.fetch(descriptor)) ?? []

        return identifiers.map { id in
            let year = Int(id)
            let filtered: [JumpSession] = if let year {
                allSessions.filter { calendar.component(.year, from: $0.startedAt) == year }
            } else {
                allSessions
            }

            let jumps = filtered.reduce(0) { $0 + $1.jumpCount }
            let calories = Int(filtered.reduce(0.0) { $0 + $1.caloriesBurned }.rounded())
            return WorkoutStatsEntity(
                totalJumps: jumps,
                sessionCount: filtered.count,
                year: year,
                caloriesBurned: calories
            )
        }
    }
}
