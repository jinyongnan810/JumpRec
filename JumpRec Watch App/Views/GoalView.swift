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
    private static let minimumCount = 100.0
    private static let maximumCount = 10000.0
    private static let countStep = 100.0

    @Binding var count: Int64
    @Binding var goalType: GoalType

    private var countBinding: Binding<Double> {
        Binding(
            get: { Double(count) },
            set: { newValue in
                let clampedValue = min(max(newValue, Self.minimumCount), Self.maximumCount)
                let snappedValue = (clampedValue / Self.countStep).rounded() * Self.countStep
                count = Int64(snappedValue)
            }
        )
    }

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
            countBinding,
            from: Self.minimumCount,
            through: Self.maximumCount,
            by: Self.countStep
        )
        .onAppear {
            goalType = .count
            count = Int64(max(Self.minimumCount, (Double(count) / Self.countStep).rounded() * Self.countStep))
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
