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
    }
}

#Preview {
    MainView()
        .environment(JumpRecSettings())
}
