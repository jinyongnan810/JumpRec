//
//  GoalSheetView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct GoalSheetView: View {
    @Bindable var settings: JumpRecSettings
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: GoalType = .count
    @State private var countValue: Int64 = DefaultJumpCount
    @State private var timeValue: Int64 = DefaultJumpTime

    var body: some View {
        VStack(spacing: 24) {
            // Drag Handle
            Capsule()
                .fill(AppColors.tabInactive)
                .frame(width: 40, height: 4)
                .padding(.top, 16)

            // Title
            Text("Set Session Goal")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            // Segmented Control
            segmentedControl

            // Value Stepper
            stepperRow

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
            selectedType = settings.goalType
            countValue = settings.jumpCount
            timeValue = settings.jumpTime
        }
    }

    // MARK: - Segmented Control

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            segmentButton(label: "Jump Count", type: .count)
            segmentButton(label: "Jump Time", type: .time)
        }
        .padding(4)
        .background(AppColors.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func segmentButton(label: String, type: GoalType) -> some View {
        let isActive = selectedType == type
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedType = type
            }
        } label: {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                .foregroundStyle(isActive ? AppColors.bgPrimary : AppColors.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(isActive ? AppColors.accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
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
        selectedType == .count ? "jumps" : "minutes"
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
}

#Preview {
    GoalSheetView(settings: JumpRecSettings())
        .presentationDetents([.medium])
        .preferredColorScheme(.dark)
}
