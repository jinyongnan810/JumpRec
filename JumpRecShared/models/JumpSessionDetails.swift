//
//  JumpSessionDetails.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/12/27.
//

import Foundation
import SwiftData

/// Represents a point in time during a session with the calculated jump rate.
/// Used to track performance over the course of a workout session.
public struct RatePoint: Codable {
    /// Time offset from the start of the session (in seconds)
    public let secondsFromStart: TimeInterval

    /// Jump rate at this point in time (jumps per minute)
    public let rate: Double

    public init(secondsFromStart: TimeInterval, rate: Double) {
        self.secondsFromStart = secondsFromStart
        self.rate = rate
    }
}

/// Stores detailed timing data for a jump rope session.
/// This model contains the raw data points (individual jump timestamps and rate measurements)
/// that complement the summary statistics in `JumpSession`.
@Model
public final class JumpSessionDetails {
    /// Reference to the parent session containing summary statistics
    public var session: JumpSession?

    /// Array of timestamps for each individual jump, stored as TimeIntervals from session start
    /// This allows reconstruction of the complete jump sequence for analysis
    public var jumps: [TimeInterval] = []

    /// Internal storage for rate points as encoded JSON data
    /// SwiftData doesn't natively support arrays of custom structs, so we encode/decode manually
    private var ratePointsData: Data?

    /// Array of rate measurements taken throughout the session
    /// Each point captures the jump rate at a specific moment in time
    public var ratePoints: [RatePoint] {
        get {
            guard let data = ratePointsData else { return [] }
            return (try? JSONDecoder().decode([RatePoint].self, from: data)) ?? []
        }
        set {
            ratePointsData = try? JSONEncoder().encode(newValue)
        }
    }

    /// Initializes session details with jump timestamps
    /// - Parameters:
    ///   - session: The parent session this data belongs to
    ///   - jumps: Array of jump timestamps (as TimeIntervals from session start)
    public init(session: JumpSession, jumps: [TimeInterval]) {
        self.session = session
        self.jumps = jumps
    }

    /// Records a rate measurement at a specific point in the session
    /// - Parameters:
    ///   - time: Absolute timestamp when the rate was measured
    ///   - rate: Jump rate at this time (jumps per minute)
    public func addRatePoint(at time: Date, rate: Double) {
        let secondsFromStart = time.timeIntervalSince(session!.startedAt)
        var points = ratePoints
        points.append(RatePoint(secondsFromStart: secondsFromStart, rate: rate))
        ratePoints = points
    }

    /// Calculates the time intervals between consecutive jumps
    /// Useful for analyzing jump rhythm and consistency
    /// - Returns: Array of time differences between jumps (in seconds)
    ///           Returns empty array if there are fewer than 2 jumps
    public func getJumpIntervals() -> [TimeInterval] {
        guard jumps.count > 1 else { return [] }
        return zip(jumps.dropFirst(), jumps).map { $0 - $1 }
    }
}
