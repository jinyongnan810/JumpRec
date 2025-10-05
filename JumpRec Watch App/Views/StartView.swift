//
//  StartView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import Combine
import JumpRecShared
import SwiftUI

let TimeString = "Time"
let MinuteString = "Minute"

struct StartView: View {
    @State var isCountingDown: Bool = false
    @State var countdown: Double = 3
    var timer = Timer.publish(every: 1, on: .main, in: .common)
    var onStart: () -> Void

    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    @State var showSettings: Bool = false

    var goal: Text {
        switch settings.goalType {
        case .count:
            return Text("^[\(settings.jumpCount) \(TimeString)](inflect: true)")
        case .time:
            return Text("^[\(settings.jumpTime) \(MinuteString)](inflect: true)")
        @unknown default:
            return Text("^[\(settings.jumpCount) \(TimeString)](inflect: true)")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isCountingDown {
                    Text("\(countdown, specifier: "%.0f")")
                        .font(.largeTitle)
                        .onReceive(timer.autoconnect()) { _ in
                            countdown -= 1
                            if countdown < 1 {
                                onStart()
                            }
                        }
                } else {
                    VStack {
                        Text("Start")
                            .font(.largeTitle)
                            .onTapGesture {
                                withAnimation {
                                    isCountingDown.toggle()
                                }
                            }
                        goal
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                GoalView()
            }
        }
    }
}

#Preview {
    StartView(onStart: {})
        .environment(JumpRecSettings())
}
