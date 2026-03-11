//
//  JumpRecLiveActivityAttributes.swift
//  JumpRecShared
//

import Foundation

#if canImport(ActivityKit)
    import ActivityKit

    @available(iOS 18.0, *)
    public struct JumpRecLiveActivityAttributes: ActivityAttributes {
        public struct ContentState: Codable, Hashable {
            public var jumpCount: Int
            public var caloriesBurned: Int
            public var averageRate: Int
            public var sourceLabel: String
            public var endedAt: Date?

            public init(
                jumpCount: Int,
                caloriesBurned: Int,
                averageRate: Int,
                sourceLabel: String,
                endedAt: Date? = nil
            ) {
                self.jumpCount = jumpCount
                self.caloriesBurned = caloriesBurned
                self.averageRate = averageRate
                self.sourceLabel = sourceLabel
                self.endedAt = endedAt
            }
        }

        public var startedAt: Date
        public var goalSummary: String

        public init(startedAt: Date, goalSummary: String) {
            self.startedAt = startedAt
            self.goalSummary = goalSummary
        }
    }
#endif
