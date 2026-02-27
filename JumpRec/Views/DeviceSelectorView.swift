//
//  DeviceSelectorView.swift
//  JumpRec
//

import SwiftUI

struct DeviceSelectorView: View {
    @State private var selected: DeviceSource = .iPhone

    var body: some View {
        HStack(spacing: 8) {
            ForEach(DeviceSource.allCases, id: \.self) { source in
                let isSelected = source == selected
                Button {
                    selected = source
                } label: {
                    Label(source.rawValue, systemImage: source.iconName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isSelected ? AppColors.bgPrimary : AppColors.textSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(isSelected ? AppColors.accent : AppColors.cardSurface)
                        .clipShape(Capsule())
                }
            }
        }
    }
}

#Preview {
    DeviceSelectorView()
        .padding()
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
