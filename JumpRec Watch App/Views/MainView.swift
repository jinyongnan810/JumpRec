//
//  MainView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

/// Chooses the correct watch screen based on the current session state.
struct MainView: View {
    /// Holds the shared watch app state.
    @State var appState = JumpRecState.shared
    /// Provides persisted goal settings.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings

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
        }
        .onChange(of: appState.jumpState) { _, newValue in
            print("current appState: \(newValue)")
        }
    }
}

#Preview {
    MainView()
        .environment(JumpRecSettings())
}
