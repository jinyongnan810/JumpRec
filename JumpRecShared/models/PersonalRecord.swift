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
    /// Longest uninterrupted jump streak achieved in a single session.
    case longestJumpStreak
    /// Longest completed session duration with a time-based goal.
    case longestSession
    /// Highest calories burned in a session.
    case mostCalories
    /// Best jump rate achieved in a session.
    case bestJumpRate
    /// Most consistent sustained pace score derived from saved rate samples.
    case steadyRhythm
    /// Highest whole-session average jump rate among qualifying sessions.
    case bestAverageJumpRate
    /// Highest calorie burn efficiency measured in kilocalories per minute.
    case sneakyBurn
    /// Highest number of double-unders achieved in a single session.
    case mostDoubleUnders

    // MARK: - Display Metadata

    /// Returns the localized display title for the record type.
    public nonisolated var title: String {
        switch self {
        case .highestJumpCount:
            String(localized: "Highest Jump Count")
        case .longestJumpStreak:
            String(localized: "Longest Jump Streak")
        case .longestSession:
            String(localized: "Longest Session")
        case .mostCalories:
            String(localized: "Most Calories")
        case .bestJumpRate:
            String(localized: "Best Jump Rate")
        case .steadyRhythm:
            String(localized: "Steady Rhythm")
        case .bestAverageJumpRate:
            String(localized: "Best Average Jump Rate")
        case .sneakyBurn:
            String(localized: "Sneaky Burn")
        case .mostDoubleUnders:
            String(localized: "Most Double Unders")
        }
    }

    /// Returns the SF Symbol used to represent the record type.
    public nonisolated var icon: String {
        switch self {
        case .highestJumpCount:
            "trophy.fill"
        case .longestJumpStreak:
            "figure.jumprope"
        case .longestSession:
            "timer"
        case .mostCalories:
            "flame.fill"
        case .bestJumpRate:
            "bolt.fill"
        case .steadyRhythm:
            "waveform.path.ecg"
        case .bestAverageJumpRate:
            "speedometer"
        case .sneakyBurn:
            "flame.circle.fill"
        case .mostDoubleUnders:
            "chevron.up.2"
        }
    }

    /// Returns the comparison rule used when evaluating new record values.
    public var comparison: PersonalRecordComparison {
        switch self {
        case .highestJumpCount, .longestJumpStreak, .longestSession, .mostCalories, .bestJumpRate, .steadyRhythm, .bestAverageJumpRate, .sneakyBurn, .mostDoubleUnders:
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

/// Cached personal records with labels and icons derived from their kind.
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
