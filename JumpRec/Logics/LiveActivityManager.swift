//
//  LiveActivityManager.swift
//  JumpRec
//

import Foundation

#if canImport(ActivityKit)
    import ActivityKit

    @MainActor
    final class LiveActivityManager {
        static let shared = LiveActivityManager()

        private var currentActivity: Activity<JumpRecLiveActivityAttributes>?

        private init() {}

        func startOrUpdate(
            startedAt: Date,
            goalSummary: String,
            jumpCount: Int,
            caloriesBurned: Double,
            averageRate: Int,
            sourceLabel: String
        ) async {
            guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

            let attributes = JumpRecLiveActivityAttributes(
                startedAt: startedAt,
                goalSummary: goalSummary
            )
            let content = ActivityContent(
                state: JumpRecLiveActivityAttributes.ContentState(
                    jumpCount: jumpCount,
                    caloriesBurned: Int(caloriesBurned.rounded()),
                    averageRate: averageRate,
                    sourceLabel: sourceLabel
                ),
                staleDate: Date().addingTimeInterval(120),
                relevanceScore: 100
            )

            if let activity = resolvedActivity {
                await activity.update(content)
                currentActivity = activity
                return
            }

            do {
                currentActivity = try Activity.request(
                    attributes: attributes,
                    content: content,
                    pushType: nil
                )
            } catch {
                print("[LiveActivityManager] Failed to start live activity: \(error)")
            }
        }

        func end(
            startedAt _: Date?,
            goalSummary _: String,
            jumpCount: Int,
            caloriesBurned: Double,
            averageRate: Int,
            sourceLabel: String,
            endedAt: Date
        ) async {
            guard let activity = resolvedActivity else { return }

            let finalContent = ActivityContent(
                state: JumpRecLiveActivityAttributes.ContentState(
                    jumpCount: jumpCount,
                    caloriesBurned: Int(caloriesBurned.rounded()),
                    averageRate: averageRate,
                    sourceLabel: sourceLabel,
                    endedAt: endedAt
                ),
                staleDate: nil,
                relevanceScore: 100
            )

            await activity.end(finalContent, dismissalPolicy: .default)
            currentActivity = nil
        }

        func endIfNeeded() async {
            for activity in Activity<JumpRecLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }

        private var resolvedActivity: Activity<JumpRecLiveActivityAttributes>? {
            if let currentActivity {
                return currentActivity
            }

            currentActivity = Activity<JumpRecLiveActivityAttributes>.activities.first
            return currentActivity
        }
    }
#else
    @MainActor
    final class LiveActivityManager {
        static let shared = LiveActivityManager()

        private init() {}

        func startOrUpdate(
            startedAt _: Date,
            goalSummary _: String,
            jumpCount _: Int,
            caloriesBurned _: Double,
            averageRate _: Int,
            sourceLabel _: String
        ) async {}

        func end(
            startedAt _: Date?,
            goalSummary _: String,
            jumpCount _: Int,
            caloriesBurned _: Double,
            averageRate _: Int,
            sourceLabel _: String,
            endedAt _: Date
        ) async {}

        func endIfNeeded() async {}
    }
#endif
