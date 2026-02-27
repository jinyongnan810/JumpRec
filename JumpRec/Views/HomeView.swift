//
//  HomeView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct HomeView: View {
    @Bindable var settings: JumpRecSettings
    @State private var showGoalSheet = false

    var goalText: String {
        if settings.goalType == .count {
            "Goal: \(settings.jumpCount.formatted()) jumps"
        } else {
            "Goal: \(settings.jumpTime) min"
        }
    }

    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 4) {
                Text("JumpRec")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Label(goalText, systemImage: "target")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textMuted)
            }

            // Hero Ring
            HeroRingView(progress: 0, centerText: "Ready", subtitle: "Tap Start to begin")

            // Device Selector
            DeviceSelectorView()

            // Start Button
            Button(action: {}) {
                Text("START SESSION")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(AppColors.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Set Goal Link
            Button {
                showGoalSheet = true
            } label: {
                Label("Set Goal", systemImage: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showGoalSheet) {
            GoalSheetView(settings: settings)
                .presentationDetents([.medium])
                .presentationDragIndicator(.hidden)
                .presentationBackground(AppColors.cardSurface)
        }
    }
}
