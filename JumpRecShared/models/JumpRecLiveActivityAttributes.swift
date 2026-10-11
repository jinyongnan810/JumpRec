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
        public struct ContentState: Codable, Hashable {
            /// Current goal text; older activities fall back to the static goal when absent.
            public var goalSummary: String?
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
                endedAt: Date? = nil,
                goalSummary: String? = nil
            ) {
                self.goalSummary = goalSummary
                self.jumpCount = jumpCount
                self.caloriesBurned = caloriesBurned
                self.averageRate = averageRate
                self.sourceLabel = sourceLabel
                self.endedAt = endedAt
            }
        }

        /// The time when the session started.
        public var startedAt: Date
        /// Initial goal used when ContentState has no goal text.
        public var goalSummary: String

        /// Creates the static attributes for a live activity.
        public init(startedAt: Date, goalSummary: String) {
            self.startedAt = startedAt
            self.goalSummary = goalSummary
        }
    }

    // Separate conformance keeps the payload nonisolated in main-actor-default targets.
    @available(iOS 18.0, *)
    nonisolated extension JumpRecLiveActivityAttributes: ActivityAttributes {}
#endif
