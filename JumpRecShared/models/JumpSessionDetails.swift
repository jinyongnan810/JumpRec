//
//  JumpSessionDetails.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/12/27.
//

import Foundation
import SwiftData

/// Compact, Codable chart payload point for a session rate series.
///
/// This is intentionally a plain Swift value type, not a SwiftData model. Completed sessions can
/// produce many rate points, and storing each point as a managed object creates unnecessary local
/// object churn and CloudKit records. The app now encodes arrays of these lightweight values into
/// `SessionRateSeries.payload` so list screens can keep loading only the session summary row while
/// detail screens decode the chart data on demand.
public struct RateSamplePoint: Codable, Sendable {
    /// Time offset from the session start, measured in whole seconds.
    public let secondOffset: Int

    /// Jump rate at this offset, in jumps per minute.
    ///
    /// A `Float` is precise enough for charting and derived pacing analytics, and keeps the encoded
    /// payload smaller than the previous `Double`-backed SwiftData row representation.
    public let rate: Float

    /// Creates one chart payload point.
    public init(secondOffset: Int, rate: Float) {
        self.secondOffset = secondOffset
        self.rate = rate
    }
}

/// One-to-one persisted payload for a session's chart rate series.
///
/// This model exists as a single child object so SwiftData can lazy-load it separately from
/// `JumpSession`. History and list screens can fetch session summaries without decoding the
/// potentially larger `payload`, while detail screens can read `JumpSession.decodedRateSamples`
/// when they actually need chart and rhythm analytics.
@Model
public final class SessionRateSeries {
    // MARK: - Stored Properties

    /// Parent session that owns this encoded series.
    ///
    /// The inverse relationship lives on `JumpSession.rateSeries` and uses cascade deletion so the
    /// blob row is removed with its session. The optional shape keeps the model compatible with
    /// CloudKit-backed SwiftData stores, where relationships should tolerate eventual sync timing.
    public var session: JumpSession?

    /// Encoded `[RateSamplePoint]` payload for the session.
    ///
    /// The value is optional so old sessions and partially synced records can exist safely. Decoding
    /// helpers treat `nil` or corrupt data as an empty series instead of crashing the detail screen.
    public var payload: Data?

    /// Number of samples encoded into `payload`.
    ///
    /// Keeping this as metadata lets diagnostics and future UI checks understand the series size
    /// without decoding the full blob first.
    public var sampleCount: Int = 0

    /// Payload format version.
    ///
    /// Versioning gives the app a clear future migration hook if the encoded representation changes
    /// from `[RateSamplePoint]` to another format.
    public var version: Int = 1

    // MARK: - Initialization

    /// Creates a persisted rate series for a session.
    public init(session: JumpSession? = nil, payload: Data? = nil, sampleCount: Int = 0, version: Int = 1) {
        self.session = session
        self.payload = payload
        self.sampleCount = sampleCount
        self.version = version
    }
}
