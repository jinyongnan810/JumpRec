//
//  DataStore.swift
//  ListIt
//
//  Created by Yuunan kin on 2025/09/06.
//

import Foundation
import Observation
import SwiftData

// MARK: - ModelContainer

extension ModelContainer {
    /// Creates a shared ModelContainer with CloudKit sync enabled.
    static func createContainer() throws -> ModelContainer {
        let schema = Schema([
            JumpSession.self,
            PersonalRecord.self,
            SessionRateSample.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            allowsSave: true,
            groupContainer: .identifier("group.com.kinn.JumpRec"),
            cloudKitDatabase: .automatic
        )

        return try ModelContainer(
            for: schema,
            configurations: [modelConfiguration]
        )
    }
}

/// Singleton data store managing SwiftData persistence for the app.
@MainActor
@Observable
public final class MyDataStore {
    /// Shared singleton instance.
    public static let shared: MyDataStore = {
        do {
            return try MyDataStore.makeSharedStore()
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()

    /// The SwiftData model container managing persistent storage.
    public let modelContainer: ModelContainer

    /// Main context for performing data operations.
    public let modelContext: ModelContext

    /// Creates the shared store and applies one-time bootstrap work.
    private static func makeSharedStore() throws -> MyDataStore {
        let modelContainer = try ModelContainer.createContainer()
        let store = MyDataStore(modelContainer: modelContainer)
        store.backfillPersonalRecordsIfNeeded()
        print("container and context initialized")
        return store
    }

    private init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        modelContext = modelContainer.mainContext
        modelContext.autosaveEnabled = true
    }

    /// Saves pending context changes when needed.
    func saveContextIfNeeded() {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }
}
