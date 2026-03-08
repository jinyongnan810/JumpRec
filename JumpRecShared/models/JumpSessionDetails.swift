//
//  JumpSessionDetails.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/12/27.
//

import Foundation
import SwiftData

/// Normalized per-time-bucket rate sample for a session.
@Model
public final class SessionRateSample {
    /// Parent session for this sample.
    public var session: JumpSession?

    /// Time offset from session start (seconds).
    public var secondOffset: Int = 0

    /// Jump rate at this offset (jumps per minute).
    public var rate: Double = 0

    public init(session: JumpSession, secondOffset: Int, rate: Double) {
        self.session = session
        self.secondOffset = secondOffset
        self.rate = rate
    }
}
