//
//  DataStore.swift
//  ListIt
//
//  Created by Yuunan kin on 2025/09/06.
//
import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: ModelContainer

extension ModelContainer {
    /// Creates a shared ModelContainer with CloudKit sync enabled
    /// The container uses an App Group to share data between the main app and watchOS app
    /// - Returns: Configured ModelContainer with CloudKit automatic sync
    /// - Throws: Error if container creation fails
    static func createContainer() throws -> ModelContainer {
        // Define the data models that will be stored
        let schema = Schema([
            JumpSession.self,
            SessionRateSample.self,
        ])

        // Configure persistent storage with App Group and CloudKit
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false, // Persist to disk
            allowsSave: true,
            groupContainer: .identifier("group.com.kinn.JumpRec"), // Shared container for app extensions
            cloudKitDatabase: .automatic // Enable CloudKit sync across devices
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}

/// Singleton data store managing SwiftData persistence for the app
/// Provides a centralized access point for all data operations with automatic CloudKit sync
/// Must be accessed from the main actor since it manages UI-bound data
@MainActor
@Observable
public class MyDataStore {
    /// Shared singleton instance
    public static let shared = MyDataStore()

    /// The SwiftData model container managing persistent storage
    public let modelContainer: ModelContainer

    /// Main context for performing data operations
    public let modelContext: ModelContext

    private init() {
        do {
            // Initialize the shared container with CloudKit enabled
            modelContainer = try ModelContainer.createContainer()
            modelContext = modelContainer.mainContext

            // Enable automatic saving when changes are made
            // This works in conjunction with CloudKit to sync changes across devices
            modelContext.autosaveEnabled = true

            print("container and context initialized")
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    // MARK: - Save

    /// Manually saves the model context
    /// Note: This is currently not used since autosaveEnabled is true
    /// Kept for potential future use cases requiring explicit save control
    private func save() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    public func addSession(session: JumpSession, rateSamples: [SessionRateSample] = []) {
        modelContext.insert(session)
        for sample in rateSamples {
            sample.session = session
            if session.rateSamples == nil {
                session.rateSamples = []
            }
            session.rateSamples?.append(sample)
            modelContext.insert(sample)
        }
        do {
            try modelContext.save()
            print("inserted session and rate samples")
            print("session: \(session)")
            print("samples: \(rateSamples.count)")
        } catch {
            print("failed to save")
        }
    }

    /// Creates a finalized session record and persists it with normalized rate samples.
    public func saveCompletedSession(
        startedAt: Date,
        endedAt: Date,
        jumpCount: Int,
        caloriesBurned: Double,
        jumpOffsets: [TimeInterval],
        averageHeartRate: Int? = nil,
        peakHeartRate: Int? = nil
    ) {
        let breakMetrics = SessionMetricsCalculator.breakMetrics(from: jumpOffsets)
        let session = JumpSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpCount,
            peakRate: 0,
            caloriesBurned: caloriesBurned,
            smallBreaksCount: breakMetrics.small,
            longBreaksCount: breakMetrics.long,
            longestStreak: breakMetrics.longestStreak,
            averageHeartRate: averageHeartRate,
            peakHeartRate: peakHeartRate
        )

        let rateSamples = SessionMetricsCalculator.makeRateSamples(
            for: session,
            jumpOffsets: jumpOffsets,
            durationSeconds: session.durationSeconds
        )

        session.peakRate = SessionMetricsCalculator.peakRate(from: rateSamples)
        session.averageRate = SessionMetricsCalculator.averageRate(
            jumpCount: session.jumpCount,
            durationSeconds: session.durationSeconds
        )

        addSession(session: session, rateSamples: rateSamples)
    }
}
