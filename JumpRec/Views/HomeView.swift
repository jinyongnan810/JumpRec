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
    /// Enable navigation transition
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

    /// Returns the ring progress for the current home-screen state.
    private var heroRingProgress: Double {
        isCountingDown ? countdownProgress : 1
    }

    /// Returns the primary ring text for the current home-screen state.
    private var heroRingCenterText: String {
        isCountingDown ? "\(countdownValue ?? 3)" : String(localized: "Ready?")
    }

    /// Returns the supporting ring label for the current home-screen state.
    private var heroRingSubtitle: String {
        isCountingDown ? String(localized: "Starting...") : String(localized: "Tap Start to begin")
    }

    /// Returns the ring color for the current home-screen state.
    private var heroRingColor: Color {
        isCountingDown ? AppColors.accent : AppColors.textMuted
    }

    /// Builds the hero ring for the current home-screen state.
    private var heroRingView: some View {
        HeroRingView(
            progress: heroRingProgress,
            color: heroRingColor,
            centerText: heroRingCenterText,
            subtitle: heroRingSubtitle
        )
    }

    // MARK: - View

    /// Renders the home screen and session-start controls.
    var body: some View {
        VStack(spacing: 32) {
            // Header
            VStack(spacing: 4) {
                Text("JumpRec")
                    .font(AppFonts.screenTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Label(goalText, systemImage: "target")
                    .font(AppFonts.heroRingSubtitle)
                    .foregroundStyle(AppColors.textMuted)
            }

            // Hero Ring / Countdown Ring
            heroRingView

            DeviceSelectorView(
                activeSource: displayedMotionSource,
                isPhoneMotionAvailable: appState.isPhoneMotionAvailable,
                isHeadphoneMotionAvailable: appState.isHeadphoneMotionAvailable,
                connectedHeadphoneName: appState.connectedHeadphoneName,
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
                    .font(AppFonts.primaryButtonLabel)
                    .foregroundStyle(primaryButtonTextColor)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: primaryButtonTint)
            .disabled(isPrimaryButtonDisabled)

            // Set Goal Link
            Button {
                showGoalSheet = true
            } label: {
                Label("Set Goal", systemImage: "target")
                    .font(AppFonts.secondaryActionLabel)
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

    /// Returns whether the app is waiting for a session-start request to finish.
    ///
    /// This is primarily used when the iPhone asks the Apple Watch to start a
    /// mirrored workout, because that handshake can take long enough that users
    /// may tap the button repeatedly unless the UI clearly reflects the pending state.
    private var isStartingSession: Bool {
        appState.sessionState == .starting
    }

    /// Returns whether the primary action button should reject input.
    private var isPrimaryButtonDisabled: Bool {
        isStartingSession
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
        if isStartingSession {
            String(localized: "Starting...")
        } else if isCountingDown {
            String(localized: "CANCEL")
        } else {
            String(localized: "START SESSION")
        }
    }

    /// Returns the text color for the primary button.
    private var primaryButtonTextColor: Color {
        isCountingDown || isStartingSession ? AppColors.textPrimary : AppColors.bgPrimary
    }

    /// Returns the tint color for the primary button.
    private var primaryButtonTint: Color {
        if isStartingSession {
            AppColors.textMuted
        } else if isCountingDown {
            AppColors.danger
        } else {
            AppColors.accent
        }
    }

    /// Starts the animated pre-session countdown.
    private func startWithCountdown() {
        guard !isCountingDown, !isStartingSession else { return }

        countdownTask = Task {
            await MainActor.run {
                countdownValue = 3
                countdownProgress = 1
            }

            // Let SwiftUI render the full ring once before starting the trim animation.
            await Task.yield()

            await MainActor.run {
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
    NavigationStack {
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
}
