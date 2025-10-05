//
//  MainView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import JumpRecShared
import SwiftUI

struct MainView: View {
    @State var appState = JumpRecState()
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    var body: some View {
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
    }
}

#Preview {
    MainView()
        .environment(JumpRecSettings())
}
