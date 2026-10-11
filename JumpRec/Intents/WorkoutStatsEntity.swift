//
//  WorkoutStatsEntity.swift
//  JumpRec
//

import AppIntents
import Foundation
import SwiftData

/// All-time or yearly workout totals exposed to Siri, Shortcuts, and Apple Intelligence.
public struct WorkoutStatsEntity: AppEntity, Identifiable, Sendable {
    /// Localized display representation for the entity type in Shortcuts.
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Workout Statistics"

    /// The default entity query used by the system to look up workout stats.
    public static let defaultQuery = WorkoutStatsQuery()

    /// Unique identifier: either the year string (e.g. "2026") or "all_time".
    public var id: String

    /// Total number of detected jumps in the period.
    @Property(title: "Total Jumps")
    public var totalJumps: Int

    /// Total number of completed workouts in the period.
    @Property(title: "Workout Count")
    public var sessionCount: Int

    /// Specific calendar year if queried for a specific year, or nil for all-time.
    @Property(title: "Year")
    public var year: Int?

    /// Total estimated calories burned across the period.
    @Property(title: "Calories Burned")
    public var caloriesBurned: Int

    /// Formats the statistics for presentation in Siri dialogs and Shortcuts results.
    public var displayRepresentation: DisplayRepresentation {
        if let year {
            return DisplayRepresentation(
                title: "\(year) Stats: \(totalJumps.formatted()) jumps",
                subtitle: "Workout count: \(sessionCount) • \(caloriesBurned) kcal"
            )
        }
        return DisplayRepresentation(
            title: "All-Time Stats: \(totalJumps.formatted()) jumps",
            subtitle: "Workout count: \(sessionCount) • \(caloriesBurned) kcal"
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

/// Resolves workout statistics for Shortcuts.
public struct WorkoutStatsQuery: EntityQuery, Sendable {
    public init() {}

    @MainActor
    public func entities(for identifiers: [String]) async throws -> [WorkoutStatsEntity] {
        try identifiers.map { id in
            let year = Int(id)
            let filtered = try MyDataStore.shared.sessionsForStatistics(year: year)

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
