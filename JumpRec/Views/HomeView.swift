//
//  HomeView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct HomeView: View {
    @Bindable var settings: JumpRecSettings
    @Bindable var appState: JumpRecState
    let isWatchAvailable: Bool
    let watchUnavailableReason: String
    var onStart: () -> Void
    @State private var showGoalSheet = false
    @State private var countdownValue: Int?
    @State private var countdownTask: Task<Void, Never>?
    @State private var countdownProgress: Double = 1.0

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

            // Hero Ring / Countdown Ring
            if isCountingDown {
                HeroRingView(
                    progress: countdownProgress,
                    centerText: "\(countdownValue ?? 3)",
                    subtitle: "Starting..."
                )
            } else {
                HeroRingView(progress: 0, centerText: "Ready", subtitle: "Tap Start to begin")
            }

            DeviceSelectorView(
                activeSource: displayedMotionSource,
                isPhoneMotionAvailable: appState.isPhoneMotionAvailable,
                isHeadphoneMotionAvailable: appState.isHeadphoneMotionAvailable,
                isWatchMotionAvailable: isWatchAvailable,
                watchUnavailableReason: watchUnavailableReason
            )

            // Start/Cancel Button
            Button {
                if isCountingDown {
                    cancelCountdown()
                } else {
                    startWithCountdown()
                }
            } label: {
                Text(primaryButtonTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(primaryButtonTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: primaryButtonTint)

            // Set Goal Link
            Button {
                showGoalSheet = true
            } label: {
                Label("Set Goal", systemImage: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.accent)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
            }
            .appGlassButton(tint: AppColors.accent)
            .disabled(isCountingDown)

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showGoalSheet) {
            GoalSheetView(settings: settings)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppColors.cardSurface)
        }
        .onDisappear {
            countdownTask?.cancel()
            countdownTask = nil
            countdownValue = nil
        }
    }

    private var isCountingDown: Bool {
        countdownValue != nil
    }

    private var displayedMotionSource: DeviceSource? {
        if let activeSource = appState.activeMotionSource {
            return activeSource
        }
        if isWatchAvailable {
            return .watch
        }
        if appState.isHeadphoneMotionAvailable {
            return .airpods
        }
        if appState.isPhoneMotionAvailable {
            return .iPhone
        }
        return nil
    }

    private var primaryButtonTitle: String {
        isCountingDown ? "CANCEL" : "START SESSION"
    }

    private var primaryButtonTextColor: Color {
        isCountingDown ? AppColors.textPrimary : AppColors.bgPrimary
    }

    private var primaryButtonTint: Color {
        isCountingDown ? AppColors.danger : AppColors.accent
    }

    private func startWithCountdown() {
        guard !isCountingDown else { return }

        countdownTask = Task {
            await MainActor.run {
                countdownValue = 3
                countdownProgress = 1
                withAnimation(.linear(duration: 3.0)) {
                    countdownProgress = 0
                }
            }

            for value in stride(from: 3, through: 1, by: -1) {
                if Task.isCancelled { return }
                await MainActor.run {
                    withAnimation {
                        countdownValue = value
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }

            if Task.isCancelled { return }
            await MainActor.run {
                countdownValue = nil
                countdownProgress = 1
                countdownTask = nil
                onStart()
            }
        }
    }

    private func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
        countdownValue = nil
        countdownProgress = 1
    }
}

#Preview {
    HomeView(
        settings: JumpRecSettings(),
        appState: JumpRecState(),
        isWatchAvailable: true,
        watchUnavailableReason: "Apple Watch is ready.",
        onStart: {}
    )
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
