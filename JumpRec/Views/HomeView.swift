//
//  HomeView.swift
//  JumpRec
//

import SwiftUI

/// Displays the pre-session start screen and countdown flow.
struct HomeView: View {
    private static let goalTransitionID = "goal-settings"

    /// The persisted goal settings displayed on the home screen.
    @Bindable var settings: JumpRecSettings
    /// The observable app state used to display device availability.
    @Bindable var appState: JumpRecState
    /// Indicates whether the watch path is available for this session.
    let isWatchAvailable: Bool
    /// Explains why the watch path is unavailable.
    let watchUnavailableReason: String
    /// Starts a new session after the countdown completes.
    var onStart: () -> Void
    /// Controls presentation of the goal sheet.
    @State private var showGoalSheet = false
    @Namespace private var navigationTransitionNamespace
    /// Tracks the active countdown value, or `nil` when idle.
    @State private var countdownValue: Int?
    /// Holds the asynchronous countdown task so it can be cancelled.
    @State private var countdownTask: Task<Void, Never>?
    /// Animates the countdown ring progress.
    @State private var countdownProgress: Double = 1.0

    // MARK: - Derived Values

    /// Returns the formatted goal summary shown under the app title.
    var goalText: String {
        if settings.goalType == .count {
            String(
                format: String(localized: "Goal: %@ jumps"),
                settings.jumpCount.formatted()
            )
        } else {
            String(
                format: String(localized: "Goal: %lld min"),
                settings.jumpTime
            )
        }
    }

    // MARK: - View

    /// Renders the home screen and session-start controls.
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
                    subtitle: String(localized: "Starting...")
                )
            } else {
                HeroRingView(
                    progress: 0,
                    centerText: String(localized: "Ready?"),
                    subtitle: String(localized: "Tap Start to begin")
                )
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
            .matchedTransitionSource(id: Self.goalTransitionID, in: navigationTransitionNamespace)
            .appGlassButton(tint: AppColors.accent)
            .disabled(isCountingDown)

            Spacer()
        }
        .padding(.horizontal, 24)
        .sheet(isPresented: $showGoalSheet) {
            GoalSheetView(settings: settings)
                .navigationTransition(.zoom(sourceID: Self.goalTransitionID, in: navigationTransitionNamespace))
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

    // MARK: - Helpers

    /// Returns whether the countdown is currently active.
    private var isCountingDown: Bool {
        countdownValue != nil
    }

    /// Chooses the best source to display before a session starts.
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

    /// Returns the title for the primary button.
    private var primaryButtonTitle: String {
        isCountingDown ? String(localized: "CANCEL") : String(localized: "START SESSION")
    }

    /// Returns the text color for the primary button.
    private var primaryButtonTextColor: Color {
        isCountingDown ? AppColors.textPrimary : AppColors.bgPrimary
    }

    /// Returns the tint color for the primary button.
    private var primaryButtonTint: Color {
        isCountingDown ? AppColors.danger : AppColors.accent
    }

    /// Starts the animated pre-session countdown.
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

    /// Cancels the active countdown and resets its UI state.
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
