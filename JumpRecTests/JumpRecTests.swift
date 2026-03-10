//
//  JumpRecTests.swift
//  JumpRecTests
//
//  Created by Yuunan kin on 2026/03/10.
//

import Foundation
import JumpRecShared
import Testing

struct JumpRecTests {
    @Test func testMakeRateSamplesForSteady150Rate() async throws {
        let startedAt = Date()
        let endedAt = startedAt.addingTimeInterval(60)
        let jumpOffsets = stride(from: 0.4, through: 60.0, by: 0.4).map(\.self)
        let session = JumpSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpOffsets.count,
            peakRate: 0,
            caloriesBurned: 0
        )

        let samples = SessionMetricsCalculator.makeRateSamples(
            for: session,
            jumpOffsets: jumpOffsets,
            durationSeconds: 60
        )

        #expect(samples.count == 12)
        #expect(samples.map(\.secondOffset) == Array(stride(from: 5, through: 60, by: 5)))
        #expect(samples.map { "\($0.rate)" } == ["144.0", "150.0", "148.0", "150.0", "148.8", "150.0", "150.0", "150.0", "150.0", "150.0", "150.0", "150.0"])
    }
}
