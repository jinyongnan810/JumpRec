//
//  GoalView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/15.
//

import JumpRecShared
import SwiftUI

struct GoalView: View {
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    var body: some View {
        @Bindable var bindableSettings = settings
        NavigationStack {
            List {
                NavigationLink {
                    CountView(
                        count: $bindableSettings.jumpCount,
                        goalType: $bindableSettings.goalType
                    )
                } label: {
                    Text("Count")
                        .font(.headline)
                }

                NavigationLink {
                    TimeView(time: $bindableSettings.jumpTime, goalType: $bindableSettings.goalType)
                } label: {
                    Text("Time")
                        .font(.headline)
                }
            }.navigationTitle("Goal Settings")
        }
    }
}

struct CountView: View {
    @Binding var count: Int64
    @Binding var goalType: GoalType
    var body: some View {
        Stepper("\(count)", value: $count, in: 100 ... 10000, step: 100)
            .focusable()
//            .digitalCrownRotation($count, in: 100...10000, step: 100)
            .onAppear {
                goalType = .count
            }
    }
}

struct TimeView: View {
    @Binding var time: Int64
    @Binding var goalType: GoalType
    var body: some View {
        Stepper("\(time)", value: $time, in: 1 ... 100, step: 1)
            .focusable()
            //            .digitalCrownRotation($count, in: 100...10000, step: 100)
            .onAppear {
                goalType = .time
            }
    }
}

#Preview {
    GoalView()
}
