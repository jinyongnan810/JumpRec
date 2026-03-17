//
//  LiveActivityManager.swift
//  JumpRec
//

import Foundation

#if canImport(ActivityKit)
    import ActivityKit

    /// Owns the app's live-activity lifecycle for active jump sessions.
    @MainActor
    final class LiveActivityManager {
        /// Shared singleton used by app state.
        static let shared = LiveActivityManager()

        /// Tracks the currently displayed live activity, if any.
        private var currentActivity: Activity<JumpRecLiveActivityAttributes>?

        /// Restricts creation to the shared singleton.
        private init() {}

        /// ⭐️Starts a live activity or updates the current one with fresh metrics.
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

        /// Ends the current live activity with final metrics.
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

        /// Immediately ends any live activity still associated with the app.
        func endIfNeeded() async {
            for activity in Activity<JumpRecLiveActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            currentActivity = nil
        }

        /// Returns the cached activity or resolves the current one from the system.
        private var resolvedActivity: Activity<JumpRecLiveActivityAttributes>? {
            if let currentActivity {
                return currentActivity
            }

            currentActivity = Activity<JumpRecLiveActivityAttributes>.activities.first
            return currentActivity
        }
    }
#else
    /// Fallback live-activity manager used when ActivityKit is unavailable.
    @MainActor
    final class LiveActivityManager {
        /// Shared singleton used by app state.
        static let shared = LiveActivityManager()

        /// Restricts creation to the shared singleton.
        private init() {}

        /// No-op fallback when ActivityKit is unavailable.
        func startOrUpdate(
            startedAt _: Date,
            goalSummary _: String,
            jumpCount _: Int,
            caloriesBurned _: Double,
            averageRate _: Int,
            sourceLabel _: String
        ) async {}

        /// No-op fallback when ActivityKit is unavailable.
        func end(
            startedAt _: Date?,
            goalSummary _: String,
            jumpCount _: Int,
            caloriesBurned _: Double,
            averageRate _: Int,
            sourceLabel _: String,
            endedAt _: Date
        ) async {}

        /// No-op fallback when ActivityKit is unavailable.
        func endIfNeeded() async {}
    }
#endif
