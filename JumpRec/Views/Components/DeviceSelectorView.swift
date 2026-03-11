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

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("MOTION SOURCE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            HStack(spacing: 10) {
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

        VStack(alignment: .leading, spacing: 6) {
            Label(source.rawValue, systemImage: source.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            Text(statusText(isAvailable: isAvailable, isActive: isActive))
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isActive ? AppColors.accent : AppColors.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(isActive ? AppColors.accent : AppColors.cardSurface, lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func statusText(isAvailable: Bool, isActive: Bool) -> String {
        if isActive {
            return "Active"
        }
        if isAvailable {
            return "Available"
        }
        return "Unavailable"
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
    DeviceSelectorView(activeSource: .airpods, isPhoneMotionAvailable: true, isHeadphoneMotionAvailable: true)
        .padding()
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
