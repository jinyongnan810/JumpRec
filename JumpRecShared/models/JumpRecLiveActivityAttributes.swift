//
//  JumpRecLiveActivityAttributes.swift
//  JumpRecShared
//

import Foundation

#if canImport(ActivityKit)
    import ActivityKit

    /// Defines the immutable and mutable data shown in the live activity.
    @available(iOS 18.0, *)
    public nonisolated struct JumpRecLiveActivityAttributes {
        /// Defines the live-updating content for the activity.
        public nonisolated struct ContentState: Codable, Hashable {
            /// The current jump count.
            public var jumpCount: Int
            /// The rounded calories burned value.
            public var caloriesBurned: Int
            /// The current average jump rate.
            public var averageRate: Int
            /// The short label for the active motion source.
            public var sourceLabel: String
            /// The timestamp when the session ended, if available.
            public var endedAt: Date?

            /// Creates a new live-activity content payload.
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

        /// The time when the session started.
        public var startedAt: Date
        /// A short summary of the session goal.
        public var goalSummary: String

        /// Creates the static attributes for a live activity.
        public init(startedAt: Date, goalSummary: String) {
            self.startedAt = startedAt
            self.goalSummary = goalSummary
        }
    }

    /// Declaring the ActivityKit conformance in an extension keeps this shared data type nonisolated
    /// even when app targets enable default MainActor isolation.
    @available(iOS 18.0, *)
    nonisolated extension JumpRecLiveActivityAttributes: ActivityAttributes {}
#endif
