//
//  GoalSheetView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI
import UIKit

struct GoalSheetView: View {
    @Bindable var settings: JumpRecSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: GoalType = .count
    @State private var countValue: Int64 = DefaultJumpCount
    @State private var timeValue: Int64 = DefaultJumpTime

    var body: some View {
        VStack(spacing: 24) {
            // Title
            Text("Set Session Goal")
                .font(.system(size: 15, weight: .semibold))
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
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
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

    private var stepperRow: some View {
        HStack(spacing: 32) {
            // Minus
            Button {
                adjustValue(by: -stepAmount)
            } label: {
                Image(systemName: "minus")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
                    .background(AppColors.bgPrimary)
                    .clipShape(Circle())
            }

            // Value display
            VStack(spacing: 4) {
                Text(displayValue)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)

                Text(unitLabel)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(minWidth: 100)

            // Plus
            Button {
                adjustValue(by: stepAmount)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 22))
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
                    .background(AppColors.bgPrimary)
                    .clipShape(Circle())
            }
        }
    }

    // MARK: - Helpers

    private var displayValue: String {
        if selectedType == .count {
            countValue.formatted()
        } else {
            "\(timeValue)"
        }
    }

    private var unitLabel: String {
        if selectedType == .time, timeValue == 1 {
            return "minute"
        }
        return selectedType == .count ? "jumps" : "minutes"
    }

    private var stepAmount: Int64 {
        selectedType == .count ? 100 : 1
    }

    private func adjustValue(by amount: Int64) {
        if selectedType == .count {
            countValue = max(100, countValue + amount)
        } else {
            timeValue = max(1, timeValue + amount)
        }
    }

    private func applyGoal() {
        if selectedType == .count {
            settings.jumpCount = countValue
        } else {
            settings.jumpTime = timeValue
        }
        settings.goalType = selectedType
    }

    private func configureSegmentedControlAppearance() {
        let selectedTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.bgPrimary),
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
        ]
        let normalTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.textSecondary),
            .font: UIFont.systemFont(ofSize: 15, weight: .semibold),
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
