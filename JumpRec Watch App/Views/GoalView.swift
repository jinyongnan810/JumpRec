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
        NavigationStack {
            List {
                NavigationLink {
                    CountView(
                        initialCount: settings.jumpCount
                    ) { count in
                        settings.jumpCount = count
                        settings.goalType = .count
                    }
                } label: {
                    goalRow(
                        titleKey: "Count",
                        systemImage: "number",
                        detail: String(
                            format: String(localized: "%@ jumps"),
                            settings.jumpCount.formatted()
                        ),
                        isSelected: settings.goalType == .count
                    )
                }
                .listRowBackground(AppColors.cardSurface)

                NavigationLink {
                    TimeView(
                        initialTime: settings.jumpTime
                    ) { time in
                        settings.jumpTime = time
                        settings.goalType = .time
                    }
                } label: {
                    goalRow(
                        titleKey: "Time",
                        systemImage: "clock",
                        detail: String(
                            format: String(localized: "%lld min"),
                            settings.jumpTime
                        ),
                        isSelected: settings.goalType == .time
                    )
                }
                .listRowBackground(AppColors.cardSurface)
            }
            .navigationTitle("Goal")
        }
    }

    /// Renders a goal option row with active-state feedback.
    private func goalRow(titleKey: LocalizedStringKey, systemImage: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 12))
                .foregroundStyle(AppColors.accent)

            Text(titleKey)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 4)

            Text(detail)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .padding(.vertical, 4)
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

    /// Dismisses the editor after the user confirms.
    @Environment(\.dismiss)
    private var dismiss
    /// Stores the editable jump-count goal.
    @State private var count: Int64
    /// Applies the confirmed count back to persisted settings.
    private let onConfirm: (Int64) -> Void

    /// Creates a count editor with a staged value.
    init(initialCount: Int64, onConfirm: @escaping (Int64) -> Void) {
        _count = State(initialValue: Int64(max(Self.minimumCount, Double(initialCount))))
        self.onConfirm = onConfirm
    }

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
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("\(count)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
                Text("JUMPS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
            }

            Button("Confirm") {
                onConfirm(count)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .focusable()
        .digitalCrownRotation(
            countBinding,
            from: Self.minimumCount,
            through: Self.maximumCount,
            by: Self.countStep
        )
        .onAppear {
            count = Int64(max(Self.minimumCount, (Double(count) / Self.countStep).rounded() * Self.countStep))
        }
        .navigationTitle("Count Goal")
    }
}

/// Lets the user edit a time-based goal with the Digital Crown.
struct TimeView: View {
    /// Dismisses the editor after the user confirms.
    @Environment(\.dismiss)
    private var dismiss
    /// Stores the editable time goal in minutes.
    @State private var time: Int64
    /// Applies the confirmed time back to persisted settings.
    private let onConfirm: (Int64) -> Void

    /// Creates a time editor with a staged value.
    init(initialTime: Int64, onConfirm: @escaping (Int64) -> Void) {
        _time = State(initialValue: max(1, initialTime))
        self.onConfirm = onConfirm
    }

    /// Renders the time-goal picker.
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text("\(time)")
                    .font(.system(size: 28, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
                Text("MINUTES")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
            }

            Button("Confirm") {
                onConfirm(time)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
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
        .navigationTitle("Time Goal")
    }
}

#Preview {
    GoalView()
        .environment(JumpRecSettings())
}
