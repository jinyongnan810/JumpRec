//
//  JumpingView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

struct JumpingView: View {
    @Binding var appState: JumpRecState
    var body: some View {
        ZStack {
            VStack {
                Text("Jumps:")
                    .font(.headline)
                Spacer()
            }
            VStack {
                Spacer()
                Text("\(appState.jumpCount)")
                    .font(.largeTitle)
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    TimerView(startTime: appState.startTime ?? Date())
                    Spacer()
                }
            }
        }.onTapGesture {
            appState.end()
        }
    }
}

#Preview {
    JumpingView(appState: .constant(JumpRecState()))
}
