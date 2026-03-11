//
//  DeviceSelectorView.swift
//  JumpRec
//

import SwiftUI
import UIKit

struct DeviceSelectorView: View {
    let activeSource: DeviceSource?
    let isPhoneMotionAvailable: Bool
    let isHeadphoneMotionAvailable: Bool
    let isWatchMotionAvailable: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MOTION SOURCE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            HStack(spacing: 10) {
                sourceCard(for: .watch, isAvailable: isWatchMotionAvailable)
                sourceCard(for: .iPhone, isAvailable: isPhoneMotionAvailable)
                sourceCard(for: .airpods, isAvailable: isHeadphoneMotionAvailable)
            }
        }
        .onAppear {
            configureSegmentedControlAppearance()
        }
    }

    @ViewBuilder
    private func sourceCard(for source: DeviceSource, isAvailable: Bool) -> some View {
        let isActive = activeSource == source

        Image(systemName: source.iconName)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(isActive ? AppColors.accent : AppColors.textPrimary)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 12)
            .padding(.vertical, 14)
            .background(AppColors.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isActive ? AppColors.accent : AppColors.cardSurface, lineWidth: 1.5)
            }
            .opacity(cardOpacity(isAvailable: isAvailable, isActive: isActive))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(source.shortName)
            .accessibilityValue(isActive ? "Active" : "Inactive")
    }

    private func cardOpacity(isAvailable: Bool, isActive: Bool) -> Double {
        if isActive {
            return 1
        }
        if isAvailable {
            return 0.72
        }
        return 0.35
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
    DeviceSelectorView(
        activeSource: .watch,
        isPhoneMotionAvailable: true,
        isHeadphoneMotionAvailable: true,
        isWatchMotionAvailable: true
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
