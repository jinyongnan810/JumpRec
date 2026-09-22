//
//  JumpRecAITools.swift
//  JumpRec
//

import Foundation
import SwiftData

#if canImport(FoundationModels)
    import FoundationModels

    // MARK: - iOS 26+ Foundation Models AI Tools

    /// An AI Tool for on-device Foundation Models to query recent jump rope workouts.
    @available(iOS 26.0, *)
    public struct GetRecentWorkoutsAITool: Tool {
        public let name = "getRecentWorkouts"
        public let description = "Retrieves recent jump rope workout sessions from JumpRec with key metrics including date, jump count, duration, calories, average rate, peak rate, longest streak, and AI recap."

        @Generable
        public struct Arguments: Sendable {
            @Guide(description: "Maximum number of recent workouts to retrieve", .range(1 ... 20))
            public var count: Int

            public init(count: Int = 5) {
                self.count = count
            }
        }

        public init() {}

        @MainActor
        public func call(arguments: Arguments) async throws -> [String] {
            let context = MyDataStore.shared.modelContainer.mainContext
            var descriptor = FetchDescriptor<JumpSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            descriptor.fetchLimit = arguments.count

            let sessions = try context.fetch(descriptor)
            return sessions.map { session in
                let date = session.startedAt.formatted(date: .abbreviated, time: .shortened)
                let duration = session.formattedDuration
                let jumps = session.jumpCount.formatted()
                let calories = Int(session.caloriesBurned.rounded())
                let peakRate = session.peakRate.map { "\(Int($0.rounded()))/min" } ?? "--"
                let avgRate = session.averageRate.map { "\(Int($0.rounded()))/min" } ?? "--"
                let streak = session.longestStreak

                return "[\(date)]: \(jumps) jumps in \(duration) | \(calories) kcal | Avg rate: \(avgRate) | Peak rate: \(peakRate) | Streak: \(streak) jumps"
            }
        }
    }

    /// An AI Tool for on-device Foundation Models to query all-time personal records in JumpRec.
    @available(iOS 26.0, *)
    public struct GetPersonalRecordsAITool: Tool {
        public let name = "getPersonalRecords"
        public let description = "Retrieves all-time personal records and milestones in JumpRec (highest jumps, best pace, longest duration, longest streak, calories)."

        @Generable
        public struct Arguments: Sendable {
            public init() {}
        }

        public init() {}

        @MainActor
        public func call(arguments _: Arguments) async throws -> [String] {
            let context = MyDataStore.shared.modelContainer.mainContext
            let descriptor = FetchDescriptor<PersonalRecord>()
            let records = try context.fetch(descriptor)

            if records.isEmpty {
                return ["No personal records achieved yet."]
            }

            return records.map { record in
                let date = record.achievedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Unknown date"
                let val = record.displayValue ?? "--"
                return "\(record.title): \(val) (Achieved on \(date))"
            }
        }
    }

    /// An AI Tool for on-device Foundation Models to compute aggregated statistics over a given time window.
    @available(iOS 26.0, *)
    public struct GetWorkoutSummaryStatsAITool: Tool {
        public let name = "getWorkoutSummaryStats"
        public let description = "Calculates aggregated jump rope workout statistics (total jumps, total sessions, total calories, total active time) across a specified time window in days."

        @Generable
        public struct Arguments: Sendable {
            @Guide(description: "Number of days back from today to include in summary (e.g. 1 for today, 7 for past week, 30 for past month)", .range(1 ... 365))
            public var days: Int

            public init(days: Int = 7) {
                self.days = days
            }
        }

        public init() {}

        @MainActor
        public func call(arguments: Arguments) async throws -> String {
            let context = MyDataStore.shared.modelContainer.mainContext
            let calendar = Calendar.current
            let cutoffDate = calendar.date(byAdding: .day, value: -arguments.days, to: Date()) ?? Date()

            let descriptor = FetchDescriptor<JumpSession>(
                predicate: #Predicate { session in
                    session.startedAt >= cutoffDate
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )

            let sessions = try context.fetch(descriptor)
            if sessions.isEmpty {
                return "No workouts recorded in the last \(arguments.days) days."
            }

            let totalJumps = sessions.reduce(0) { $0 + $1.jumpCount }
            let totalCalories = Int(sessions.reduce(0.0) { $0 + $1.caloriesBurned }.rounded())
            let totalSeconds = sessions.reduce(0) { $0 + $1.durationSeconds }
            let totalMinutes = totalSeconds / 60
            let remainderSeconds = totalSeconds % 60
            let formattedTime = String(format: "%02d:%02d", totalMinutes, remainderSeconds)
            let sessionCount = sessions.count

            return """
            Summary for the past \(arguments.days) days:
            - Workouts completed: \(sessionCount)
            - Total jumps: \(totalJumps.formatted())
            - Total active time: \(formattedTime)
            - Total calories burned: \(totalCalories) kcal
            - Average jumps per workout: \(totalJumps / max(sessionCount, 1))
            """
        }
    }

    /// An AI Tool for on-device Foundation Models to filter workouts by minimum jump count.
    @available(iOS 26.0, *)
    public struct SearchWorkoutsAITool: Tool {
        public let name = "searchWorkouts"
        public let description = "Searches workout history for sessions meeting specific criteria like minimum jump count."

        @Generable
        public struct Arguments: Sendable {
            @Guide(description: "Minimum jumps completed in session", .range(1 ... 10000))
            public var minimumJumps: Int

            @Guide(description: "Maximum number of matching workouts to return", .range(1 ... 15))
            public var limit: Int

            public init(minimumJumps: Int = 100, limit: Int = 5) {
                self.minimumJumps = minimumJumps
                self.limit = limit
            }
        }

        public init() {}

        @MainActor
        public func call(arguments: Arguments) async throws -> [String] {
            let context = MyDataStore.shared.modelContainer.mainContext
            let minCount = arguments.minimumJumps
            let descriptor = FetchDescriptor<JumpSession>(
                predicate: #Predicate { session in
                    session.jumpCount >= minCount
                },
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )

            let matches = try context.fetch(descriptor)
            return matches.prefix(arguments.limit).map { session in
                let date = session.startedAt.formatted(date: .abbreviated, time: .shortened)
                let duration = session.formattedDuration
                return "[\(date)]: \(session.jumpCount.formatted()) jumps in \(duration) (\(Int(session.caloriesBurned.rounded())) kcal)"
            }
        }
    }

    /// An AI Tool for on-device Foundation Models to query all-time or yearly jump stats (total jumps and session count).
    @available(iOS 26.0, *)
    public struct GetAggregatedWorkoutStatsAITool: Tool {
        public let name = "getAggregatedWorkoutStats"
        public let description = "Calculates total jump count, workout session count, total active time, and calories for either all-time or a specific calendar year (e.g. 2026, 2025)."

        @Generable
        public struct Arguments: Sendable {
            @Guide(description: "Specific calendar year to query (e.g. 2026, 2025), or leave nil for all-time stats")
            public var year: Int?

            public init(year: Int? = nil) {
                self.year = year
            }
        }

        public init() {}

        @MainActor
        public func call(arguments: Arguments) async throws -> String {
            let context = MyDataStore.shared.modelContainer.mainContext
            let calendar = Calendar.current
            let descriptor = FetchDescriptor<JumpSession>(
                sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
            )
            let allSessions = try context.fetch(descriptor)

            let filteredSessions: [JumpSession]
            let periodDescription: String
            if let targetYear = arguments.year {
                filteredSessions = allSessions.filter { calendar.component(.year, from: $0.startedAt) == targetYear }
                periodDescription = "\(targetYear)"
            } else {
                filteredSessions = allSessions
                periodDescription = "All-time"
            }

            guard !filteredSessions.isEmpty else {
                return "No workouts found for \(periodDescription)."
            }

            let totalJumps = filteredSessions.reduce(0) { $0 + $1.jumpCount }
            let totalCalories = Int(filteredSessions.reduce(0.0) { $0 + $1.caloriesBurned }.rounded())
            let totalSeconds = filteredSessions.reduce(0) { $0 + $1.durationSeconds }
            let formattedTime = String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
            let sessionCount = filteredSessions.count

            return """
            \(periodDescription) Statistics:
            - Workout sessions: \(sessionCount)
            - Total jumps: \(totalJumps.formatted())
            - Total active time: \(formattedTime)
            - Total calories: \(totalCalories) kcal
            """
        }
    }

    // MARK: - Assistant Session Orchestrator

    /// Manager providing conversational intelligence over jump rope workouts using on-device Foundation Models.
    @available(iOS 26.0, *)
    @MainActor
    public final class JumpRecAIAssistant {
        public static let shared = JumpRecAIAssistant()

        private var session: LanguageModelSession?

        private init() {}

        /// Creates or resets the language model session configured with JumpRec AI fitness tools.
        public func makeSession() -> LanguageModelSession {
            let tools: [any Tool] = [
                GetRecentWorkoutsAITool(),
                GetPersonalRecordsAITool(),
                GetWorkoutSummaryStatsAITool(),
                SearchWorkoutsAITool(),
                GetAggregatedWorkoutStatsAITool(),
            ]

            let instructions = Instructions(
                """
                You are an intelligent fitness coach and workout assistant integrated into JumpRec, an iOS jump rope tracking app.
                Your role is to help users understand their jump rope workout performance, track progress over time, review personal records, and celebrate milestones.
                You have access to tools to fetch recent workouts, inspect all-time personal records, and calculate aggregated summary statistics.
                Be encouraging, concise, supportive, and accurate.
                Never fabricate workout data, dates, or personal records that were not returned by tools.
                """
            )

            let session = LanguageModelSession(
                model: SystemLanguageModel.default,
                tools: tools,
                instructions: instructions
            )
            self.session = session
            return session
        }

        /// Queries the fitness assistant with a user request.
        public func ask(_ userPrompt: String) async throws -> String {
            let activeSession = session ?? makeSession()
            let response = try await activeSession.respond(to: userPrompt)
            return response.content
        }
    }

#endif
