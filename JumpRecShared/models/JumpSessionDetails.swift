//
//  JumpSessionDetails.swift
//  JumpRec
//
//  Created by kinn on 2025/12/27.
//

import Foundation
import SwiftData

/// Codable rate sample stored in the session's chart payload.
public nonisolated struct RateSamplePoint: Codable, Sendable, Equatable {
    /// Time offset from the session start, measured in whole seconds.
    public let secondOffset: Int

    /// Jump rate in jumps per minute, stored as a Float to keep the payload compact.
    public let rate: Float

    /// Creates one chart payload point.
    public init(secondOffset: Int, rate: Float) {
        self.secondOffset = secondOffset
        self.rate = rate
    }
}

/// Stores a session's chart series separately for lazy loading.
@Model
public final class SessionRateSeries {
    // MARK: - Stored Properties

    /// Owning session; an optional inverse relationship supports CloudKit sync and cascade deletion.
    public var session: JumpSession?

    /// Encoded rate samples; missing or corrupt payloads decode as an empty series.
    public var payload: Data?

    /// Sample count available without decoding the payload.
    public var sampleCount: Int = 0

    /// Version of the encoded payload format.
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
