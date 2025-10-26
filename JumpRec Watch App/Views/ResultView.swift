//
//  ResultView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

struct ResultView: View {
    @Binding var appState: JumpRecState
    var body: some View {
        NavigationStack {
            VStack {
                Text("Session Result")
                    .font(.caption)
                    .bold()
                Text("\(appState.jumpCount) jumps")
                    .font(.largeTitle)

                Text("in \(appState.totalTime)")
                    .font(.title)
            }.toolbar {
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        appState.reset()
                    } label: {
                        Text("Close").padding()
                    }
                }
            }
        }
    }
}

#Preview {
    ResultView(appState: .constant(JumpRecState()))
}
