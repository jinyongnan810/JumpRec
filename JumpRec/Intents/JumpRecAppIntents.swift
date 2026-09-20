//
//  JumpRecAppIntents.swift
//  JumpRec
//

import AppIntents
import Foundation
import SwiftData

// MARK: - Goal Type App Enum

/// Selectable workout goal types exposed to Siri and Shortcuts.
public enum WorkoutGoalType: String, AppEnum, Sendable {
    case openTarget
    case count
    case time

    public static var typeDisplayRepresentation: TypeDisplayRepresentation = "Workout Goal Type"

    public static var caseDisplayRepresentations: [WorkoutGoalType: DisplayRepresentation] = [
        .openTarget: "Open Workout",
        .count: "Jump Count Goal",
        .time: "Time Duration Goal",
    ]
}

// MARK: - Get Latest Workout Intent

/// Siri App Intent to inspect the user's most recent jump rope workout session.
public struct GetLatestWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Latest Workout"
    public static var description = IntentDescription("Retrieves your most recent jump rope workout from JumpRec.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<JumpSessionEntity?> & ProvidesDialog {
        let context = MyDataStore.shared.modelContainer.mainContext
        var descriptor = FetchDescriptor<JumpSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1

        guard let latest = try? context.fetch(descriptor).first else {
            return .result(
                value: nil,
                dialog: IntentDialog("No jump rope workouts found in JumpRec.")
            )
        }

        let entity = JumpSessionEntity(from: latest)
        let date = latest.startedAt.formatted(date: .abbreviated, time: .shortened)
        let jumps = latest.jumpCount.formatted()
        let duration = latest.formattedDuration
        let calories = Int(latest.caloriesBurned.rounded())
        let dialogMessage = "Your last workout was on \(date): \(jumps) jumps in \(duration), burning \(calories) kcal."

        return .result(
            value: entity,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

// MARK: - Get Today's Jump Stats Intent

/// Siri App Intent to query today's aggregated jump rope metrics.
public struct GetTodayJumpStatsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Today's Jump Stats"
    public static var description = IntentDescription("Checks how many jumps and workouts you have completed today.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let context = MyDataStore.shared.modelContainer.mainContext
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        let descriptor = FetchDescriptor<JumpSession>(
            predicate: #Predicate { session in
                session.startedAt >= startOfToday
            },
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )

        let todaySessions = (try? context.fetch(descriptor)) ?? []

        if todaySessions.isEmpty {
            return .result(
                value: 0,
                dialog: IntentDialog("You haven't logged any jump rope workouts today yet.")
            )
        }

        let totalJumps = todaySessions.reduce(0) { $0 + $1.jumpCount }
        let totalCalories = Int(todaySessions.reduce(0.0) { $0 + $1.caloriesBurned }.rounded())
        let count = todaySessions.count

        let sessionLabel = count == 1 ? "1 workout" : "\(count) workouts"
        let dialogMessage = "Today you've completed \(sessionLabel) with \(totalJumps.formatted()) total jumps, burning \(totalCalories) kcal."

        return .result(
            value: totalJumps,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

// MARK: - Get Workout Stats Intent (All-Time & Yearly)

/// Siri App Intent to query aggregated workout metrics (total jumps and workout sessions) for all time or a specific calendar year.
public struct GetWorkoutStatsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Get Workout Stats"
    public static var description = IntentDescription("Calculates total jump count, workout count, and calories for all time or a specific year in JumpRec.")

    @Parameter(title: "Year")
    public var year: Int?

    public init() {
        year = nil
    }

    public init(year: Int?) {
        self.year = year
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<WorkoutStatsEntity> & ProvidesDialog {
        let context = MyDataStore.shared.modelContainer.mainContext
        let calendar = Calendar.current

        let descriptor = FetchDescriptor<JumpSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        let allSessions = (try? context.fetch(descriptor)) ?? []

        let targetYear = year
        let filteredSessions: [JumpSession] = if let targetYear {
            allSessions.filter { session in
                calendar.component(.year, from: session.startedAt) == targetYear
            }
        } else {
            allSessions
        }

        let totalJumps = filteredSessions.reduce(0) { $0 + $1.jumpCount }
        let sessionCount = filteredSessions.count
        let totalCalories = Int(filteredSessions.reduce(0.0) { $0 + $1.caloriesBurned }.rounded())

        let statsEntity = WorkoutStatsEntity(
            totalJumps: totalJumps,
            sessionCount: sessionCount,
            year: targetYear,
            caloriesBurned: totalCalories
        )

        if filteredSessions.isEmpty {
            let emptyMessage = if let targetYear {
                "No jump rope workouts recorded for \(targetYear) in JumpRec."
            } else {
                "No jump rope workouts recorded in JumpRec yet."
            }
            return .result(
                value: statsEntity,
                dialog: IntentDialog(stringLiteral: emptyMessage)
            )
        }

        let sessionLabel = sessionCount == 1 ? "1 workout" : "\(sessionCount) workouts"
        let dialogMessage = if let targetYear {
            "In \(targetYear), you completed \(sessionLabel) with \(totalJumps.formatted()) total jumps, burning \(totalCalories) kcal."
        } else {
            "All time, you have completed \(sessionLabel) with \(totalJumps.formatted()) total jumps, burning \(totalCalories) kcal."
        }

        return .result(
            value: statsEntity,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

// MARK: - Get Personal Records Intent

/// Siri App Intent to inspect the user's best personal records.
public struct GetPersonalRecordsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Check Personal Records"
    public static var description = IntentDescription("Inspects your personal records and milestones in JumpRec.")

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[PersonalRecordEntity]> & ProvidesDialog {
        let context = MyDataStore.shared.modelContainer.mainContext
        let descriptor = FetchDescriptor<PersonalRecord>()
        let records = (try? context.fetch(descriptor)) ?? []

        if records.isEmpty {
            return .result(
                value: [],
                dialog: IntentDialog("No personal records achieved yet. Complete a workout to set your first records!")
            )
        }

        let entities = records.map { PersonalRecordEntity(from: $0) }

        // Find key milestone highlights for spoken dialog
        let highestJumpRecord = records.first(where: { $0.kind == .highestJumpCount })
        let longestStreakRecord = records.first(where: { $0.kind == .longestJumpStreak })
        let bestRateRecord = records.first(where: { $0.kind == .bestJumpRate })

        var highlights: [String] = []
        if let highest = highestJumpRecord, let val = highest.displayValue {
            highlights.append("highest count is \(val)")
        }
        if let streak = longestStreakRecord, let val = streak.displayValue {
            highlights.append("longest streak is \(val)")
        }
        if let rate = bestRateRecord, let val = rate.displayValue {
            highlights.append("peak rate is \(val)")
        }

        let dialogMessage = if !highlights.isEmpty {
            "Your personal records: " + highlights.joined(separator: ", ") + "."
        } else {
            "You have \(records.count) personal records recorded in JumpRec."
        }

        return .result(
            value: entities,
            dialog: IntentDialog(stringLiteral: dialogMessage)
        )
    }
}

// MARK: - Search Workouts Intent

/// Siri App Intent to search past jump rope sessions.
public struct SearchWorkoutsIntent: AppIntent {
    public static var title: LocalizedStringResource = "Search Workouts"
    public static var description = IntentDescription("Searches your jump rope workout history in JumpRec.")

    @Parameter(title: "Search Query")
    public var query: String

    public init() {
        query = ""
    }

    public init(query: String) {
        self.query = query
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ReturnsValue<[JumpSessionEntity]> & ProvidesDialog {
        let results = try await JumpSessionQuery().entities(matching: query)

        if results.isEmpty {
            return .result(
                value: [],
                dialog: IntentDialog("No workouts found matching \"\(query)\".")
            )
        } else {
            let count = results.count
            let message = count == 1
                ? "Found 1 matching jump rope workout."
                : "Found \(count) matching jump rope workouts."
            return .result(
                value: results,
                dialog: IntentDialog(stringLiteral: message)
            )
        }
    }
}

// MARK: - Start Workout Intent

/// Siri App Intent to launch the app and start a jump rope workout.
public struct StartWorkoutIntent: AppIntent {
    public static var title: LocalizedStringResource = "Start Jump Rope Workout"
    public static var description = IntentDescription("Opens JumpRec and begins a jump rope workout.")

    /// Opening the app is required so CoreMotion sensors and audio cues can run in the active session.
    public static var openAppWhenRun: Bool = true

    @Parameter(title: "Goal Type", default: .openTarget)
    public var goalType: WorkoutGoalType

    @Parameter(title: "Target Value")
    public var targetValue: Int?

    public init() {
        goalType = .openTarget
        targetValue = nil
    }

    public init(goalType: WorkoutGoalType, targetValue: Int? = nil) {
        self.goalType = goalType
        self.targetValue = targetValue
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog {
        // Map intent goal type to JumpRec's internal GoalType
        let resolvedGoalType: GoalType
        let resolvedGoalValue: Int

        switch goalType {
        case .count:
            resolvedGoalType = .count
            resolvedGoalValue = targetValue ?? Int(DefaultJumpCount)
        case .time:
            resolvedGoalType = .time
            resolvedGoalValue = targetValue ?? Int(DefaultJumpTime)
        case .openTarget:
            // An open workout starts with count goal of 0 or a high default
            resolvedGoalType = .count
            resolvedGoalValue = targetValue ?? 1000
        }

        if let state = JumpRecState.current, state.sessionState == .idle {
            state.start(
                goalType: resolvedGoalType,
                goalValue: resolvedGoalValue
            )
        } else {
            // Queue pending start for when ContentView loads
            JumpRecState.pendingStartGoal = (type: resolvedGoalType, value: resolvedGoalValue)
        }

        let dialogMessage = switch goalType {
        case .count:
            "Starting a \(resolvedGoalValue) jump workout in JumpRec."
        case .time:
            "Starting a \(resolvedGoalValue) minute jump rope workout in JumpRec."
        case .openTarget:
            "Starting jump rope workout in JumpRec."
        }

        return .result(dialog: IntentDialog(stringLiteral: dialogMessage))
    }
}
