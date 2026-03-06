//
//  DeviceSelectorView.swift
//  JumpRec
//

import SwiftUI
import UIKit

struct DeviceSelectorView: View {
    @State private var selected: DeviceSource = .iPhone

    var body: some View {
        Picker("Device", selection: $selected) {
            ForEach(DeviceSource.allCases, id: \.self) { source in
                Label(source.rawValue, systemImage: source.iconName).tag(source)
            }
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
        .tint(AppColors.accent)
        .onAppear {
            configureSegmentedControlAppearance()
        }
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
    DeviceSelectorView()
        .padding()
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
