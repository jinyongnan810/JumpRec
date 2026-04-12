//
//  ContentView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import SwiftUI

struct ContentView: View {
    @State private var connectivityMangaer = ConnectivityManager.shared
    @State private var appState = JumpRecState.shared

    var body: some View {
        MainView()
            .onAppear {
                // Prime speech once when the root watch UI appears so the first workout
                // announcement is not delayed by the synthesizer's one-time setup cost.
                appState.warmUpSpeechSynthesizerIfNeeded()
            }
    }
}

#Preview {
    ContentView()
        .environment(JumpRecSettings())
}
