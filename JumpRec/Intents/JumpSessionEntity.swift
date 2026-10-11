//
//  JumpSessionEntity.swift
//  JumpRec
//

import AppIntents
import Foundation
import SwiftData

/// Completed workout statistics exposed to Siri, Shortcuts, and Apple Intelligence.
public struct JumpSessionEntity: AppEntity, Identifiable, Sendable {
    /// Localized display representation for the entity type in Shortcuts and Siri interfaces.
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Jump Rope Workout"

    /// The default entity query used by the system to look up workouts by ID or search criteria.
    public static let defaultQuery = JumpSessionQuery()

    /// Unique identifier of the workout session.
    public var id: UUID

    /// Timestamp when the workout started.
    @Property(title: "Start Time")
    public var startedAt: Date

    /// Total duration of the workout in seconds.
    @Property(title: "Duration Seconds")
    public var durationSeconds: Int

    /// Total number of detected jumps completed during the session.
    @Property(title: "Jump Count")
    public var jumpCount: Int

    /// Estimated calories burned during the session.
    @Property(title: "Calories Burned")
    public var caloriesBurned: Double

    /// Peak jump rate achieved during the session (jumps per minute).
    @Property(title: "Peak Rate")
    public var peakRate: Double?

    /// Average jump rate across the entire session (jumps per minute).
    @Property(title: "Average Rate")
    public var averageRate: Double?

    /// Longest uninterrupted jump streak without a break.
    @Property(title: "Longest Streak")
    public var longestStreak: Int

    /// Formats the entity for presentation in Siri dialogs, Spotlight search, and Shortcuts results.
    public var displayRepresentation: DisplayRepresentation {
        let minutes = durationSeconds / 60
        let seconds = durationSeconds % 60
        let durationFormatted = String(format: "%02d:%02d", minutes, seconds)
        let dateFormatted = startedAt.formatted(date: .abbreviated, time: .shortened)
        let caloriesFormatted = "\(Int(caloriesBurned.rounded())) kcal"

        return DisplayRepresentation(
            title: "\(jumpCount.formatted()) jumps",
            subtitle: "\(dateFormatted) • \(durationFormatted) • \(caloriesFormatted)"
        )
    }

    /// Memberwise initializer for testing or synthetic entity creation.
    public init(
        id: UUID,
        startedAt: Date,
        durationSeconds: Int,
        jumpCount: Int,
        caloriesBurned: Double,
        peakRate: Double? = nil,
        averageRate: Double? = nil,
        longestStreak: Int = 0
    ) {
        self.id = id
        self.startedAt = startedAt
        self.durationSeconds = durationSeconds
        self.jumpCount = jumpCount
        self.caloriesBurned = caloriesBurned
        self.peakRate = peakRate
        self.averageRate = averageRate
        self.longestStreak = longestStreak
    }

    /// Creates an entity snapshot from a persisted `JumpSession` model object.
    public init(from session: JumpSession) {
        id = session.id
        startedAt = session.startedAt
        durationSeconds = session.durationSeconds
        jumpCount = session.jumpCount
        caloriesBurned = session.caloriesBurned
        peakRate = session.peakRate
        averageRate = session.averageRate
        longestStreak = session.longestStreak
    }
}

/// Resolves workouts for Siri, Shortcuts, and Spotlight.
public struct JumpSessionQuery: EntityQuery, EntityStringQuery, Sendable {
    public init() {}

    /// Resolves entities matching a list of unique identifiers.
    @MainActor
    public func entities(for identifiers: [UUID]) async throws -> [JumpSessionEntity] {
        let context = MyDataStore.shared.modelContainer.mainContext
        guard !identifiers.isEmpty else { return [] }
        let targetIDs = identifiers
        // Resolve the batch in SQLite rather than materializing the entire history.
        let descriptor = FetchDescriptor<JumpSession>(
            predicate: #Predicate { targetIDs.contains($0.id) },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        return try context.fetch(descriptor).map { JumpSessionEntity(from: $0) }
    }

    /// Provides suggested workout entities for parameter pickers (returns up to 20 most recent).
    @MainActor
    public func suggestedEntities() async throws -> [JumpSessionEntity] {
        let context = MyDataStore.shared.modelContainer.mainContext
        var descriptor = FetchDescriptor<JumpSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 20
        let sessions = try context.fetch(descriptor)
        return sessions.map { JumpSessionEntity(from: $0) }
    }

    /// Matches workouts by query string (e.g. matching date, jump count number, or AI comment notes).
    @MainActor
    public func entities(matching string: String) async throws -> [JumpSessionEntity] {
        let query = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else {
            return try await suggestedEntities()
        }

        let context = MyDataStore.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<JumpSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let sessions = try context.fetch(descriptor)

        // Filter in memory for string matching across jump count and dates
        let matches = sessions.filter { session in
            let countText = "\(session.jumpCount)"
            let dateText = session.startedAt.formatted(date: .abbreviated, time: .omitted).lowercased()

            return countText.contains(query) ||
                dateText.contains(query)
        }

        return matches.prefix(20).map { JumpSessionEntity(from: $0) }
    }
}
