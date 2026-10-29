//
//  SettingsView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/09/15.
//

import SwiftUI

/// Displays watch settings including goals, jump detection sensitivity, and audio cues.
struct SettingsView: View {
    /// Provides the persisted settings being edited.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings

    /// Inverts the threshold adjustment so sliding right increases sensitivity.
    private var sensitivitySliderBinding: Binding<Double> {
        Binding(
            get: { -settings.jumpDetectorThresholdAdjustmentPercentage },
            set: { settings.jumpDetectorThresholdAdjustmentPercentage = -$0 }
        )
    }

    /// Formats the detector sensitivity tier for display in the settings section.
    private var thresholdAdjustmentDisplayValue: String {
        let roundedPercentage = Int(settings.jumpDetectorThresholdAdjustmentPercentage.rounded())
        switch roundedPercentage {
        case ..<(-20):
            return String(localized: "High")
        case -20 ... -5:
            return String(localized: "Slightly High")
        case 5 ... 20:
            return String(localized: "Slightly Low")
        case 21...:
            return String(localized: "Low")
        default:
            return String(localized: "Standard")
        }
    }

    /// Renders the watch settings list.
    var body: some View {
        @Bindable var settings = settings

        List {
            Section("Membership") {
                if settings.hasUnlockedUnlimitedWorkouts {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(AppFonts.watchBody)
                            .foregroundStyle(AppColors.accent)
                        Text("Unlimited Active")
                            .font(AppFonts.watchBody)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Free Workouts")
                                .font(AppFonts.watchBody)
                                .foregroundStyle(AppColors.textPrimary)
                            Spacer()
                            Text("\(settings.qualifiedWorkoutCount) / \(JumpRecSettings.freeWorkoutQuota)")
                                .font(AppFonts.watchGoalChip)
                                // Match the iPhone quota milestone styling even when all workouts are used.
                                .foregroundStyle(AppColors.accent)
                        }

                        if settings.isQuotaExceeded {
                            Text("Limit reached. Consider unlocking on iPhone.")
                                .font(AppFonts.watchSupportingRegular)
                                .foregroundStyle(AppColors.accent)
                        } else {
                            Text("100+ jump workouts")
                                .font(AppFonts.watchSupportingRegular)
                                .foregroundStyle(AppColors.textMuted)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Goal") {
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
            }

            Section("Audio Settings") {
                Toggle(
                    isOn: $settings.shouldSpeakJumpCountAnnouncements,
                    label: {
                        Text("Speak Jump Count")
                            .font(AppFonts.watchBody)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                )
                .tint(AppColors.accent)

                Toggle(
                    isOn: $settings.shouldSpeakJumpTimeAnnouncements,
                    label: {
                        Text("Speak Jump Time")
                            .font(AppFonts.watchBody)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                )
                .tint(AppColors.accent)
            }

            Section("Jump Detection") {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sensitivity")
                            .font(AppFonts.watchBody)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text(thresholdAdjustmentDisplayValue)
                            .font(AppFonts.watchGoalChip)
                            .foregroundStyle(AppColors.accent)
                    }
                    Slider(
                        value: sensitivitySliderBinding,
                        in: MinimumJumpDetectorThresholdAdjustmentPercentage ... MaximumJumpDetectorThresholdAdjustmentPercentage,
                        step: 5
                    )
                    .tint(AppColors.accent)
                }
                .padding(.vertical, 4)
            }

            Section("Permissions") {
                PermissionsSettingsContent()
            }
        }
        .navigationTitle("Settings")
    }

    /// Formats the row value so selected state is announced without relying on the checkmark symbol alone.
    private func accessibilityValue(detail: String, isSelected: Bool) -> String {
        guard isSelected else { return detail }
        return String(
            format: String(localized: "%@, selected"),
            detail
        )
    }

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

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(AppFonts.watchSupportingRegular)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 18, alignment: .trailing)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.5), value: isSelected)
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(titleKey))
        .accessibilityValue(Text(accessibilityValue(detail: detail, isSelected: isSelected)))
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
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Jump count goal"))
            .accessibilityValue(
                Text(
                    String(
                        format: String(localized: "%@ jumps"),
                        count.formatted()
                    )
                )
            )
            .accessibilityHint(Text("Turn the Digital Crown to adjust the count."))

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
    /// Raw Digital Crown position scaled to minutes for finer adjustments.
    @State private var rawTimeValue: Double
    /// Applies the confirmed time back to persisted settings.
    private let onConfirm: (Int64) -> Void

    /// Creates a time editor with a staged value.
    init(initialTime: Int64, onConfirm: @escaping (Int64) -> Void) {
        _rawTimeValue = State(initialValue: Double(max(1, initialTime) * 100))
        self.onConfirm = onConfirm
    }

    /// Renders the time-goal picker.
    var body: some View {
        VStack(spacing: 12) {
            VStack(spacing: 8) {
                Text(timeDisplayText)
                    .font(AppFonts.watchGoalValue)
                    .foregroundStyle(AppColors.accent)
                Text("MINUTES")
                    .font(AppFonts.watchMetricLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Jump time goal"))
            .accessibilityValue(
                Text(
                    String(
                        format: String(localized: "%lld minutes"),
                        Int64(scaledTimeValue.rounded())
                    )
                )
            )
            .accessibilityHint(Text("Turn the Digital Crown to adjust the time."))

            Button("Confirm") {
                // Convert the scaled crown position to the stored integer minute goal.
                onConfirm(Int64(scaledTimeValue.rounded()))
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.accent)
        }
        .focusable()
        .digitalCrownRotation(
            $rawTimeValue,
            from: 100,
            through: 10000,
            by: 1
        )
        .navigationTitle("Time Goal")
    }

    // MARK: - Helpers

    /// Converts the raw Digital Crown position into the minute value shown to the user.
    private var scaledTimeValue: Double {
        rawTimeValue / 100
    }

    /// Formats the staged duration in minutes.
    private var timeDisplayText: String {
        scaledTimeValue.formatted(.number.precision(.fractionLength(0)))
    }
}

#Preview {
    SettingsView()
        .environment(JumpRecSettings())
}

#if DEBUG
    #Preview("10 Free Workouts Used") {
        // Show the exhausted membership state without persisting sample quota or goal edits.
        SettingsView()
            .environment(JumpRecSettings(previewQualifiedWorkoutCount: JumpRecSettings.freeWorkoutQuota))
    }
#endif
