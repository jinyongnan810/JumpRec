//
//  MainView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftData
import SwiftUI

/// Chooses the correct watch screen based on the current session state.
struct MainView: View {
    /// Holds the shared watch app state.
    @State var appState = JumpRecState.shared
    /// Provides persisted goal settings.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings

    /// Provides access to the shared data store.
    @Environment(MyDataStore.self) var myDataStore

    /// Observes saved sessions for debugging and refresh verification.
    @Query(filter: nil, sort: [SortDescriptor(\JumpSession.startedAt)]) var jumpSessions: [JumpSession]
    /// Renders the current watch screen for the session lifecycle.
    var body: some View {
        ZStack {
            switch appState.jumpState {
            case .idle:
                StartView(
                    onStart: {
                        appState
                            .start(
                                goalType: settings.goalType,
                                goalCount: settings.goalCount
                            )
                    })
            case .finished:
                ResultView(appState: appState)
            case .jumping:
                JumpingView(appState: appState)
            }
        }.onChange(of: appState.jumpState) { _, newValue in
            print("current appState: \(newValue)")
        }
        .onChange(of: jumpSessions) { _, newValue in
            print("🔥jumpSessions: \(newValue.count)")
        }
        .onAppear {
            do {
                let results = try myDataStore.modelContext.fetch(FetchDescriptor<JumpSession>())
                for result in results {
                    print(
                        "⭐️fetched: \(result.startedAt),\(result.endedAt),\(result.jumpCount),\(result.caloriesBurned)"
                    )
                    print("rate samples: \(result.rateSamples?.count ?? 0)")
                }
            } catch {
                print("failed to fetch: \(error)")
            }
        }
    }
}

#Preview {
    MainView()
        .environment(JumpRecSettings())
        .modelContainer(MyDataStore.shared.modelContainer)
        .environment(MyDataStore.shared)
}
