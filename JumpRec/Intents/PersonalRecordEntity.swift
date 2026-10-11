//
//  PersonalRecordEntity.swift
//  JumpRec
//

import AppIntents
import Foundation
import SwiftData

/// Personal record exposed to Siri and Shortcuts.
public struct PersonalRecordEntity: AppEntity, Identifiable, Sendable {
    /// Localized display representation for the entity type in Shortcuts and Siri interfaces.
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Personal Record"

    /// The default entity query used by the system to look up personal records.
    public static let defaultQuery = PersonalRecordQuery()

    /// Unique string identifier corresponding to the personal record kind (e.g. "highestJumpCount").
    public var id: String

    /// Localized title for the record type (e.g. "Highest Jump Count").
    @Property(title: "Record Type")
    public var title: String

    /// Formatted value achieved (e.g. "1,500 jumps", "180/min", "15:00").
    @Property(title: "Record Value")
    public var displayValue: String

    /// Date and time when this record was set.
    @Property(title: "Achieved Date")
    public var achievedAt: Date?

    /// Formats the record entity for Siri dialogs and Shortcuts list views.
    public var displayRepresentation: DisplayRepresentation {
        let dateString = achievedAt?.formatted(date: .abbreviated, time: .shortened) ?? ""
        let subtitle: LocalizedStringResource = dateString.isEmpty ? "" : "Achieved \(dateString)"

        return DisplayRepresentation(
            title: "\(title): \(displayValue)",
            subtitle: subtitle
        )
    }

    /// Memberwise initializer for testing or synthetic creation.
    public init(
        id: String,
        title: String,
        displayValue: String,
        achievedAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.displayValue = displayValue
        self.achievedAt = achievedAt
    }

    /// Creates an entity snapshot from a persisted `PersonalRecord` model object.
    public init(from record: PersonalRecord) {
        id = record.kind.rawValue
        title = record.title
        displayValue = record.displayValue ?? ""
        achievedAt = record.achievedAt
    }
}

/// Resolves personal records for Siri and Shortcuts.
public struct PersonalRecordQuery: EntityQuery, Sendable {
    public init() {}

    /// Resolves record entities matching a list of record identifiers.
    @MainActor
    public func entities(for identifiers: [String]) async throws -> [PersonalRecordEntity] {
        let context = MyDataStore.shared.modelContainer.mainContext
        let targetIDs = Set(identifiers)
        let descriptor = FetchDescriptor<PersonalRecord>()
        let records = try context.fetch(descriptor)
        return records
            .filter { targetIDs.contains($0.kind.rawValue) }
            .map { PersonalRecordEntity(from: $0) }
    }

    /// Returns all current personal records.
    @MainActor
    public func suggestedEntities() async throws -> [PersonalRecordEntity] {
        let context = MyDataStore.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<PersonalRecord>()
        let records = try context.fetch(descriptor)
        return records.map { PersonalRecordEntity(from: $0) }
    }
}
