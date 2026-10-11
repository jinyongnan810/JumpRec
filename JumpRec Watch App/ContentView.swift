//
//  ContentView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/09/13.
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
                // Warm up speech on first appearance to reduce the first workout cue's delay.
                appState.warmUpSpeechSynthesizerIfNeeded()
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
    }

    /// Refreshes speech after long background periods, ignoring brief wrist-down transitions.
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

#Preview("100 Free Workouts Used") {
    // Tapping Start in this idle preview shows quota help.
    ContentView()
        .environment(JumpRecSettings(previewQualifiedWorkoutCount: JumpRecSettings.freeWorkoutQuota))
}
