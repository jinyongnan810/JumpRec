//
//  MainView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import JumpRecShared
import SwiftData
import SwiftUI

struct MainView: View {
    @State var appState = JumpRecState()
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings

    @Environment(MyDataStore.self) var myDataStore

    // doesn't work
    @Query(filter: nil, sort: [SortDescriptor(\JumpSession.startedAt)]) var jumpSessions: [JumpSession]
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
                ResultView(appState: $appState)
            case .jumping:
                JumpingView(appState: $appState)
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
                    print("details: \(result.details?.jumps)")
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
}
