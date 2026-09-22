//
//  JumpRecShortcutsProvider.swift
//  JumpRec
//

import AppIntents

/// Registers out-of-the-box Siri voice shortcuts and Spotlight capabilities for JumpRec.
///
/// Users can invoke these shortcuts immediately using Siri voice commands without needing to manually
/// configure anything in the Shortcuts app first.
public struct JumpRecShortcutsProvider: AppShortcutsProvider {
    /// Background color theme for JumpRec shortcuts tiles.
    public static let shortcutTileColor: ShortcutTileColor = .orange

    /// Defines the zero-setup App Shortcuts available to Siri, Spotlight, and the Shortcuts app.
    public static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: GetLatestWorkoutIntent(),
            phrases: [
                "Get latest workout in \(.applicationName)",
                "Last workout in \(.applicationName)",
                "Check last workout in \(.applicationName)",
                "How did I do in my last jump in \(.applicationName)",
            ],
            shortTitle: "Latest Workout",
            systemImageName: "figure.jumprope"
        )

        AppShortcut(
            intent: GetTodayJumpStatsIntent(),
            phrases: [
                "Today's jumps in \(.applicationName)",
                "How many jumps today in \(.applicationName)",
                "Today's workout in \(.applicationName)",
                "Check today's workout in \(.applicationName)",
            ],
            shortTitle: "Today's Jumps",
            systemImageName: "chart.bar.fill"
        )

        AppShortcut(
            intent: GetPersonalRecordsIntent(),
            phrases: [
                "Check personal records in \(.applicationName)",
                "Show my records in \(.applicationName)",
                "My jump records in \(.applicationName)",
                "What are my best jump stats in \(.applicationName)",
            ],
            shortTitle: "Personal Records",
            systemImageName: "trophy.fill"
        )

        AppShortcut(
            intent: StartWorkoutIntent(),
            phrases: [
                "Start jump rope in \(.applicationName)",
                "Start workout in \(.applicationName)",
                "Start jumping in \(.applicationName)",
            ],
            shortTitle: "Start Workout",
            systemImageName: "play.fill"
        )

        AppShortcut(
            intent: GetWorkoutStatsIntent(),
            phrases: [
                "All time jumps in \(.applicationName)",
                "Total jumps in \(.applicationName)",
                "How many jumps all time in \(.applicationName)",
                "Total workouts in \(.applicationName)",
                "Workout stats in \(.applicationName)",
                "Check workout stats in \(.applicationName)",
                "Get workout statistics in \(.applicationName)",
            ],
            shortTitle: "Workout Stats",
            systemImageName: "chart.xyaxis.line"
        )
    }
}
