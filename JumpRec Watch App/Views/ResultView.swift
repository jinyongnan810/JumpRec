//
//  ResultView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

struct ResultView: View {
    @Binding var appState: JumpRecState
    var jumpCount: AttributedString {
        var str = AttributedString(String(appState.jumpCount))
        str.foregroundColor = .blue
        str.font = .title2.bold()
        return str
    }

    var totalTime: AttributedString {
        var str = AttributedString(appState.totalTime)
        str.foregroundColor = .blue
        str.font = .title3.bold()
        return str
    }

    var totalEnergy: AttributedString {
        var str = AttributedString(String(appState.energyBurned))
        str.foregroundColor = .blue
        str.font = .subheadline.bold()
        return str
    }

    var body: some View {
        NavigationStack {
            VStack {
                Text("Session Result")
                    .font(.caption)
                    .bold()
                Text("\(jumpCount) jumps")
                    .font(.title2)

                Text("in \(totalTime)")
                    .font(.title3)

                Text("(\(totalEnergy)Kcal)")
                    .font(.subheadline)
            }.toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.reset()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
    }
}

#Preview {
    ResultView(appState: .constant(JumpRecState()))
}
