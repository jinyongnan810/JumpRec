//
//  PersonalRecord.swift
//  JumpRec
//

import Foundation
import SwiftData

/// Stable identifiers for persisted personal records.
public enum PersonalRecordKind: String, Codable, CaseIterable, Sendable {
    /// Highest jump count achieved in a single session.
    case highestJumpCount
    /// Longest completed session duration.
    case longestSession
    /// Highest calories burned in a session.
    case mostCalories
    /// Best jump rate achieved in a session.
    case bestJumpRate

    // MARK: - Display Metadata

    /// Returns the localized display title for the record type.
    public var title: String {
        switch self {
        case .highestJumpCount:
            "Highest Jump Count"
        case .longestSession:
            "Longest Session"
        case .mostCalories:
            "Most Calories"
        case .bestJumpRate:
            "Best Jump Rate"
        }
    }

    /// Returns the SF Symbol used to represent the record type.
    public var icon: String {
        switch self {
        case .highestJumpCount:
            "trophy.fill"
        case .longestSession:
            "timer"
        case .mostCalories:
            "flame.fill"
        case .bestJumpRate:
            "bolt.fill"
        }
    }

    /// Returns the comparison rule used when evaluating new record values.
    public var comparison: PersonalRecordComparison {
        switch self {
        case .highestJumpCount, .longestSession, .mostCalories, .bestJumpRate:
            .largerIsBetter
        }
    }
}

/// Defines how new metric values should be compared against saved records.
public enum PersonalRecordComparison: String, Codable, Sendable {
    /// Higher values replace older records.
    case largerIsBetter
    /// Lower values replace older records.
    case smallerIsBetter

    /// Returns whether a new metric beats the current saved value.
    public func isBetter(newValue: Double, than currentValue: Double) -> Bool {
        switch self {
        case .largerIsBetter:
            newValue > currentValue
        case .smallerIsBetter:
            newValue < currentValue
        }
    }
}

/// Cached personal-record rows updated when a session is saved.
/// Display metadata is derived from the record kind so UI labels and icons stay consistent.
@Model
public final class PersonalRecord {
    // MARK: - Stored Properties

    /// Persists the record kind as a stable raw string.
    public var kindRawValue: String?
    /// Persists the comparable numeric record value.
    public var metricValue: Double?
    /// Persists the formatted display string for UI use.
    public var displayValue: String?
    /// Stores when the record was achieved.
    public var achievedAt: Date?

    // MARK: - Derived Properties

    /// Converts the stored raw value into a typed record kind.
    public var kind: PersonalRecordKind {
        get { PersonalRecordKind(rawValue: kindRawValue ?? "") ?? .highestJumpCount }
        set { kindRawValue = newValue.rawValue }
    }

    /// Returns the display title for the stored record kind.
    public var title: String {
        kind.title
    }

    /// Returns the SF Symbol for the stored record kind.
    public var icon: String {
        kind.icon
    }

    // MARK: - Initialization

    /// Creates a cached personal record entry.
    public init(
        kind: PersonalRecordKind,
        metricValue: Double,
        displayValue: String,
        achievedAt: Date
    ) {
        kindRawValue = kind.rawValue
        self.metricValue = metricValue
        self.displayValue = displayValue
        self.achievedAt = achievedAt
    }
}
