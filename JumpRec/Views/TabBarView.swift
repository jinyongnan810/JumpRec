//
//  TabBarView.swift
//  JumpRec
//

import SwiftUI

struct TabBarView: View {
    @Binding var selectedTab: Tab

    var body: some View {
        HStack(spacing: 0) {
            TabBarItem(
                icon: "house.fill",
                label: "HOME",
                isSelected: selectedTab == .home
            ) {
                selectedTab = .home
            }

            TabBarItem(
                icon: "chart.bar.fill",
                label: "HISTORY",
                isSelected: selectedTab == .history
            ) {
                selectedTab = .history
            }
        }
        .padding(4)
        .frame(height: 62)
        .background(AppColors.cardSurface)
        .clipShape(Capsule())
    }
}

#Preview {
    TabBarView(selectedTab: .constant(.home))
        .padding(.horizontal, 16)
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}

private struct TabBarItem: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))

                Text(label)
                    .font(.system(size: 10, weight: isSelected ? .semibold : .medium, design: .monospaced))
                    .tracking(2)
            }
            .foregroundStyle(isSelected ? AppColors.accent : AppColors.tabInactive)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
