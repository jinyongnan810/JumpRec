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

    /// Matches the timing used by the row animation so follow-up symbol effects
    /// can wait until the layout and opacity changes have settled.
    private static let selectionAnimationDuration = 0.3
    /// The row delays its selection animation slightly to wait for screen navigation
    private static let selectionAnimationDelay = 0.2

    /// Renders a goal option row with active-state feedback.
    @ViewBuilder
    private func goalRow(titleKey: LocalizedStringKey, systemImage: String, detail: String, isSelected: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(AppFonts.watchBody)
                .foregroundStyle(AppColors.accent)

            Text(titleKey)
                .font(AppFonts.watchSectionTitle)
                .foregroundStyle(AppColors.textPrimary)

            Spacer(minLength: 4)

            Text(detail)
                .font(AppFonts.watchGoalChip)
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            SelectionIndicatorView(
                isSelected: isSelected,
                symbolEffectDelay: Self.selectionAnimationDuration + Self.selectionAnimationDelay
            )
        }
        .animation(
            .easeInOut(duration: Self.selectionAnimationDuration)
                .delay(Self.selectionAnimationDelay),
            value: isSelected
        )
        .padding(.vertical, 4)
    }
}

/// Displays the goal row's selection indicator and delays its symbol effect
/// until the enclosing row has finished expanding the trailing slot.
private struct SelectionIndicatorView: View {
    /// Indicates whether the enclosing goal row is currently selected.
    let isSelected: Bool
    /// Describes how long the row's layout animation takes so the symbol effect
    /// can start after the visual state change has completed.
    let symbolEffectDelay: Double

    /// Triggers value-driven symbol effects on older watchOS versions.
    @State private var symbolEffectTrigger = 0
    /// Controls the draw-on effect on newer watchOS versions after the delay.
    @State private var isDrawEffectActive = true

    var body: some View {
        let checkMark = Image(systemName: "checkmark.circle.fill")
            .font(AppFonts.watchSupportingRegular)
            .foregroundStyle(AppColors.accent)

        Group {
            if #available(watchOS 26.0, *) {
                checkMark
                    .symbolEffect(
                        .drawOn.byLayer,
                        options: .speed(0.5),
                        isActive: isDrawEffectActive
                    )
            } else {
                checkMark
                    .symbolEffect(
                        .bounce,
                        options: .speed(0.5),
                        value: symbolEffectTrigger
                    )
            }
        }
        .opacity(isSelected ? 1 : 0)
        .frame(maxWidth: isSelected ? nil : 0)
        .task(id: isSelected) {
            // Reset immediately when the row is deselected so a later selection
            // can replay the effect from a known baseline.
            isDrawEffectActive = isSelected

            do {
                try await Task.sleep(for: .seconds(symbolEffectDelay))
            } catch {
                // SwiftUI cancels the task if the selection flips quickly. That
                // cancellation is expected because the delayed symbol effect
                // should not play for a stale selection state.
                return
            }

            if #available(watchOS 26.0, *) {
                isDrawEffectActive = !isSelected
            } else {
                symbolEffectTrigger += 1
            }
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
                    .font(AppFonts.watchGoalValue)
                    .foregroundStyle(AppColors.accent)
                Text("JUMPS")
                    .font(AppFonts.watchMetricLabel)
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
                    .font(AppFonts.watchGoalValue)
                    .foregroundStyle(AppColors.accent)
                Text("MINUTES")
                    .font(AppFonts.watchMetricLabel)
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
