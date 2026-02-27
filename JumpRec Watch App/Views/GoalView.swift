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
                    HStack(spacing: 8) {
                        Image(systemName: "number")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.accent)
                        Text("Count")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .listRowBackground(AppColors.cardSurface)

                NavigationLink {
                    TimeView(time: $bindableSettings.jumpTime, goalType: $bindableSettings.goalType)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColors.accent)
                        Text("Time")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColors.textPrimary)
                    }
                }
                .listRowBackground(AppColors.cardSurface)
            }
            .navigationTitle("Goal")
        }
    }
}

struct CountView: View {
    @Binding var count: Int64
    @Binding var goalType: GoalType
    var body: some View {
        VStack(spacing: 8) {
            Text("\(count)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
            Text("JUMPS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)
        }
        .focusable()
        .digitalCrownRotation(
            Binding(
                get: { Double(count) },
                set: { count = Int64($0) }
            ),
            from: 100,
            through: 10000,
            by: 100
        )
        .onAppear {
            goalType = .count
        }
    }
}

struct TimeView: View {
    @Binding var time: Int64
    @Binding var goalType: GoalType
    var body: some View {
        VStack(spacing: 8) {
            Text("\(time)")
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.accent)
            Text("MINUTES")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)
        }
        .focusable()
        .digitalCrownRotation(
            Binding(
                get: { Double(time) },
                set: { time = Int64($0) }
            ),
            from: 1,
            through: 100,
            by: 1
        )
        .onAppear {
            goalType = .time
        }
    }
}

#Preview {
    GoalView()
        .environment(JumpRecSettings())
}
