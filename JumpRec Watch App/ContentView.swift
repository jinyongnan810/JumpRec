//
//  ContentView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import Foundation
import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var connectivityMangaer = ConnectivityManager.shared
    @State private var appState = JumpRecState.shared
    @State private var enteredBackgroundAt: Date?

    var body: some View {
        MainView()
            .onAppear {
                // Prime speech once when the root watch UI appears so the first workout
                // announcement is not delayed by the synthesizer's one-time setup cost.
                appState.warmUpSpeechSynthesizerIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
    }

    /// Tracks long background periods so stale watchOS audio state can be refreshed.
    ///
    /// Short inactive/background transitions are common while the user lowers their wrist.
    /// Waiting a few minutes avoids disrupting normal in-workout prompts while still
    /// recovering the speech pipeline before a later session starts after days away.
    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .active:
            guard let enteredBackgroundAt else {
                appState.warmUpSpeechSynthesizerIfNeeded()
                return
            }

            let backgroundDuration = Date().timeIntervalSince(enteredBackgroundAt)
            self.enteredBackgroundAt = nil
            if backgroundDuration >= 300 {
                appState.recoverSpeechAudioPipelineAfterExtendedBackground()
            } else {
                appState.warmUpSpeechSynthesizerIfNeeded()
            }
        case .background:
            enteredBackgroundAt = Date()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

#Preview {
    ContentView()
        .environment(JumpRecSettings())
}
