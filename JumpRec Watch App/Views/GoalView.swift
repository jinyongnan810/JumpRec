//
//  GoalView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/15.
//

import SwiftUI

/// Displays the watch goal selection menu.
struct GoalView: View {
    /// Provides the persisted settings being edited.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    /// Renders the watch goal selection navigation.
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

/// Lets the user edit a count-based goal with the Digital Crown.
struct CountView: View {
    /// The minimum selectable jump count.
    private static let minimumCount = 100.0
    /// The maximum selectable jump count.
    private static let maximumCount = 10000.0
    /// The step size used when rotating the crown.
    private static let countStep = 100.0

    /// Binds the selected jump-count goal.
    @Binding var count: Int64
    /// Binds the selected goal type.
    @Binding var goalType: GoalType

    /// Converts the integer count binding into a crown-friendly double binding.
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

    /// Renders the count-goal picker.
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

/// Lets the user edit a time-based goal with the Digital Crown.
struct TimeView: View {
    /// Binds the selected time goal in minutes.
    @Binding var time: Int64
    /// Binds the selected goal type.
    @Binding var goalType: GoalType
    /// Renders the time-goal picker.
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
