//
//  PersonalRecord.swift
//  JumpRec
//

import Foundation
import SwiftData

/// Stable identifiers for persisted personal records.
public enum PersonalRecordKind: String, Codable, CaseIterable, Sendable {
    case highestJumpCount
    case longestSession
    case mostCalories
    case bestJumpRate

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

    public var comparison: PersonalRecordComparison {
        switch self {
        case .highestJumpCount, .longestSession, .mostCalories, .bestJumpRate:
            .largerIsBetter
        }
    }
}

public enum PersonalRecordComparison: String, Codable, Sendable {
    case largerIsBetter
    case smallerIsBetter

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
    public var kindRawValue: String?
    public var metricValue: Double?
    public var displayValue: String?
    public var achievedAt: Date?

    public var kind: PersonalRecordKind {
        get { PersonalRecordKind(rawValue: kindRawValue ?? "") ?? .highestJumpCount }
        set { kindRawValue = newValue.rawValue }
    }

    public var title: String {
        kind.title
    }

    public var icon: String {
        kind.icon
    }

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
