//
//  GoalSheetView.swift
//  JumpRec
//

import SwiftUI
import UIKit

/// Lets the user choose a count-based or time-based workout goal.
struct GoalSheetView: View {
    /// The persisted settings being edited by the sheet.
    @Bindable var settings: JumpRecSettings
    /// Dismisses the sheet after changes are applied.
    @Environment(\.dismiss) private var dismiss

    // MARK: - View State

    /// Tracks the selected goal type while editing.
    @State private var selectedType: GoalType = .count
    /// Tracks the editable jump-count goal value.
    @State private var countValue: Int64 = DefaultJumpCount
    /// Tracks the editable time goal value in minutes.
    @State private var timeValue: Int64 = DefaultJumpTime

    // MARK: - View

    /// Renders the goal-selection controls and confirmation button.
    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Set Session Goal")
                .font(AppFonts.primaryButtonLabel)
                .foregroundStyle(AppColors.textPrimary)

            // Segmented Control
            segmentedControl

            // Value Stepper
            stepperRow.animation(.easeInOut, value: selectedType)

            Spacer()

            // Confirm Button
            Button {
                applyGoal()
                dismiss()
            } label: {
                Text("Confirm")
                    .font(AppFonts.primaryButtonLabel)
                    .foregroundStyle(AppColors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: AppColors.accent)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.cardSurface)
        .onAppear {
            configureSegmentedControlAppearance()
            selectedType = settings.goalType
            countValue = settings.jumpCount
            timeValue = settings.jumpTime
        }.padding(.top, 20)
    }

    // MARK: - Segmented Control

    /// Switches between count and time goal editing.
    private var segmentedControl: some View {
        Picker("Goal Type", selection: $selectedType) {
            Text("Jump Count")
//                .font(.system(size: 15, weight: .semibold))
                .tag(GoalType.count)
            Text("Jump Time")
//                .font(.system(size: 15, weight: .semibold))
                .tag(GoalType.time)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
//        .tint(AppColors.accent)
    }

    // MARK: - Stepper Row

    /// Displays the stepper controls for the active goal type.
    private var stepperRow: some View {
        HStack(spacing: 32) {
            // Minus
            Button {
                adjustValue(by: -stepAmount)
            } label: {
                Image(systemName: "minus")
                    .font(AppFonts.largeControlIcon)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
            }
            .appGlassButton(tint: AppColors.accent)
            .buttonBorderShape(.circle)

            // Value display
            VStack(spacing: 4) {
                Text(displayValue)
                    .font(AppFonts.metricValueXLMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())

                Text(unitLabel)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(minWidth: 100)

            // Plus
            Button {
                adjustValue(by: stepAmount)
            } label: {
                Image(systemName: "plus")
                    .font(AppFonts.largeControlIcon)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
            }
            .appGlassButton(tint: AppColors.accent)
            .buttonBorderShape(.circle)
        }
    }

    // MARK: - Helpers

    /// Returns the value currently shown in the editor.
    private var displayValue: String {
        if selectedType == .count {
            countValue.formatted()
        } else {
            "\(timeValue)"
        }
    }

    /// Returns the unit label for the currently selected goal type.
    private var unitLabel: String {
        if selectedType == .time, timeValue == 1 {
            return String(localized: "minute")
        }
        return selectedType == .count ? String(localized: "jumps") : String(localized: "minutes")
    }

    /// Returns the step size used when adjusting the current goal.
    private var stepAmount: Int64 {
        selectedType == .count ? 100 : 1
    }

    /// Increments or decrements the active goal value while respecting minimums.
    private func adjustValue(by amount: Int64) {
        withAnimation {
            if selectedType == .count {
                countValue = max(100, countValue + amount)
            } else {
                timeValue = max(1, timeValue + amount)
            }
        }
    }

    /// Writes the edited goal values back to persisted settings.
    private func applyGoal() {
        if selectedType == .count {
            settings.jumpCount = countValue
        } else {
            settings.jumpTime = timeValue
        }
        settings.goalType = selectedType
    }

    /// Applies the custom UIKit appearance used by the segmented control.
    private func configureSegmentedControlAppearance() {
        let selectedTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.bgPrimary),
            .font: AppFonts.segmentedControlLabel,
        ]
        let normalTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.textSecondary),
            .font: AppFonts.segmentedControlLabel,
        ]

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppColors.accent)
        UISegmentedControl.appearance().setTitleTextAttributes(normalTextAttributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(selectedTextAttributes, for: .selected)
    }
}

#Preview {
    GoalSheetView(settings: JumpRecSettings())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
}
