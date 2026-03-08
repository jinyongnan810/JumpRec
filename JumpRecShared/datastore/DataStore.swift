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
        smallBreaksCount: Int = 0,
        longBreaksCount: Int = 0,
        jumpOffsets: [TimeInterval],
        bucketSeconds: Int = 5,
        rollingWindowSeconds: Int = 30
    ) {
        let session = JumpSession(
            startedAt: startedAt,
            endedAt: endedAt,
            jumpCount: jumpCount,
            peakRate: 0,
            caloriesBurned: caloriesBurned,
            smallBreaksCount: smallBreaksCount,
            longBreaksCount: longBreaksCount
        )

        let rateSamples = buildRateSamples(
            for: session,
            jumpOffsets: jumpOffsets,
            durationSeconds: session.durationSeconds,
            bucketSeconds: bucketSeconds,
            rollingWindowSeconds: rollingWindowSeconds
        )

        session.peakRate = rateSamples.map(\.rate).max()
        if session.durationSeconds > 0 {
            session.averageRate = Double(session.jumpCount) * 60.0 / Double(session.durationSeconds)
        }

        addSession(session: session, rateSamples: rateSamples)
    }

    /// Builds fixed-interval rolling jump-rate samples (jumps/minute).
    private func buildRateSamples(
        for session: JumpSession,
        jumpOffsets: [TimeInterval],
        durationSeconds: Int,
        bucketSeconds: Int = 5,
        rollingWindowSeconds: Int = 30
    ) -> [SessionRateSample] {
        guard durationSeconds > 0 else { return [] }

        var samples: [SessionRateSample] = []
        var left = 0
        var right = 0
        let sorted = jumpOffsets.sorted()

        for second in stride(from: 0, through: durationSeconds, by: bucketSeconds) {
            let upperBound = Double(second)
            let lowerBound = Double(max(0, second - rollingWindowSeconds))

            while left < sorted.count, sorted[left] <= lowerBound {
                left += 1
            }
            while right < sorted.count, sorted[right] <= upperBound {
                right += 1
            }

            let countInWindow = max(0, right - left)
            let effectiveWindowSeconds = min(rollingWindowSeconds, max(1, second))
            let rate = Double(countInWindow) * 60.0 / Double(effectiveWindowSeconds)
            samples.append(SessionRateSample(session: session, secondOffset: second, rate: rate))
        }

        return samples
    }
}
