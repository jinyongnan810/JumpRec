//
//  HomeView.swift
//  JumpRec
//

import SwiftUI

/// Displays the primary home tab, supporting pre-session readiness, animated countdown,
/// and live active workout session state directly in-place.
struct HomeView: View {
    private static let settingsTransitionID = "settings"

    /// The persisted goal settings displayed on the home screen.
    @Bindable var settings: JumpRecSettings
    /// The observable app state used to display pre-session and live active-session progress.
    @Bindable var appState: JumpRecState
    /// Starts a new session after the countdown completes.
    var onStart: () -> Void
    /// Stops the active local session.
    var onStop: () -> Void

    @Environment(MyDataStore.self) private var dataStore
    @State private var purchaseManager = PurchaseManager.shared

    // MARK: - View State

    /// Controls presentation of the paywall sheet when the 100-workout quota is reached.
    @State private var showPaywall = false
    /// Controls presentation of the settings sheet.
    @State private var showSettingsView = false
    /// Coordinates the gear-button zoom transition with the presented settings sheet.
    @Namespace private var navigationTransitionNamespace
    /// Tracks the active countdown value, or `nil` when idle.
    @State private var countdownValue: Int?
    /// Holds the asynchronous countdown task so it can be cancelled.
    @State private var countdownTask: Task<Void, Never>?
    /// Animates the countdown ring progress.
    @State private var countdownProgress: Double = 1.0

    /// Tracks the current time for live active elapsed-time updates.
    @State private var now = Date()
    /// Animates the progress ring fill during an active session.
    @State private var animatedProgress: Double = 0
    /// Animates the primary ring text during an active session.
    @State private var animatedCenterText = "0"
    /// Animates the ring subtitle text during an active session.
    @State private var animatedRingSubtitle = ""

    // MARK: - Derived Values: Pre-Session & Shared

    /// Returns the formatted goal summary shown under the app title when idle.
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

    /// Returns the title for the primary pre-session action button.
    private var primaryButtonTitle: String {
        if isStartingSession {
            String(localized: "Starting...")
        } else if isCountingDown {
            String(localized: "CANCEL")
        } else {
            String(localized: "START WORKOUT")
        }
    }

    /// Returns the text color for the primary pre-session button.
    private var primaryButtonTextColor: Color {
        isCountingDown || isStartingSession ? AppColors.textPrimary : AppColors.bgPrimary
    }

    /// Returns the tint color for the primary pre-session button.
    private var primaryButtonTint: Color {
        if isStartingSession {
            AppColors.textMuted
        } else if isCountingDown {
            AppColors.danger
        } else {
            AppColors.accent
        }
    }

    // MARK: - Derived Values: Active Session

    /// Returns the active goal value for the current session.
    private var goalValue: Int64 {
        if let mirroredGoalValue = appState.sessionGoalValue {
            return Int64(mirroredGoalValue)
        }
        return settings.goalType == .count ? settings.jumpCount : settings.jumpTime
    }

    /// Returns the active goal type for the current session.
    private var goalType: GoalType {
        appState.sessionGoalType ?? settings.goalType
    }

    /// Returns normalized progress toward the session goal during an active session.
    private var activeProgress: Double {
        guard goalValue > 0 else { return 0 }
        if goalType == .count {
            return min(1.0, Double(appState.jumpCount) / Double(goalValue))
        } else {
            let goalSeconds = goalValue * 60
            return min(1.0, Double(elapsedSeconds) / Double(goalSeconds))
        }
    }

    /// Returns the active goal text shown in the header while a session is running.
    private var activeGoalText: String {
        if goalType == .count {
            String(
                format: String(localized: "Goal: %@ jumps"),
                goalValue.formatted()
            )
        } else {
            String(
                format: String(localized: "Goal: %lld min"),
                goalValue
            )
        }
    }

    /// Returns the subtitle shown below the hero-ring value during an active session.
    private var activeRingSubtitle: String {
        if goalType == .count {
            String(
                format: String(localized: "/ %@ jumps"),
                goalValue.formatted()
            )
        } else {
            String(
                format: String(localized: "/ %lld min"),
                goalValue
            )
        }
    }

    /// Returns the main value shown in the hero ring during an active session.
    private var activeRingCenterText: String {
        if goalType == .count {
            "\(appState.jumpCount)"
        } else {
            "\(elapsedSeconds / 60)"
        }
    }

    /// Returns a VoiceOver label for the active hero ring.
    private var activeRingAccessibilityLabel: String {
        goalType == .count ? String(localized: "Jump progress") : String(localized: "Time progress")
    }

    /// Returns a VoiceOver value describing the active ring's numerical progress.
    private var activeRingAccessibilityValue: String {
        if goalType == .count {
            return String(
                format: String(localized: "%@ of %@ jumps"),
                appState.jumpCount.formatted(),
                goalValue.formatted()
            )
        }
        return String(
            format: String(localized: "%lld of %lld minutes"),
            Int64(elapsedSeconds / 60),
            goalValue
        )
    }

    /// Returns the leading stat card label based on the active goal type.
    private var leadingStatLabel: LocalizedStringKey {
        goalType == .count ? "TIME" : "JUMPS"
    }

    /// Returns the leading stat card value based on the active goal type.
    private var leadingStatValue: String {
        goalType == .count ? elapsedFormatted : appState.jumpCount.formatted()
    }

    /// Returns the live elapsed time formatted as `mm:ss`.
    private var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    /// Returns the live elapsed time in seconds.
    private var elapsedSeconds: Int {
        guard let startTime = appState.startTime else { return 0 }
        return max(0, Int(now.timeIntervalSince(startTime)))
    }

    /// Returns the live current heart-rate text, or a placeholder until HealthKit delivers samples.
    private var heartRateText: String {
        guard let heartRate = appState.heartRate else { return "--" }
        return "\(heartRate) bpm"
    }

    /// Returns the compact symbol used in the active-session header badge.
    private var deviceSourceIconName: String {
        appState.activeMotionSource?.iconName ?? "iphone.slash"
    }

    /// Returns a VoiceOver label for the active device source badge.
    private var deviceSourceAccessibilityLabel: String {
        if let activeMotionSource = appState.activeMotionSource {
            return String(
                format: String(localized: "Tracking with %@"),
                activeMotionSource.shortName
            )
        }
        return String(localized: "Starting motion tracking")
    }

    /// Keeps the live stat cards in two equal columns.
    private var statColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    /// Returns the localized slider prompt for ending active jump sessions.
    private var stopSliderText: String {
        String(localized: "STOP WORKOUT")
    }

    /// Returns the localized hint explaining the stop slider action.
    private var stopSliderAccessibilityHint: String {
        String(localized: "Ends the current jump workout.")
    }

    /// Returns the slider tint for active session controls.
    private var stopSliderTint: Color {
        AppColors.warning
    }

    // MARK: - Unified Hero Ring State Mapping

    /// Returns the ring progress for the current home-screen state.
    private var heroRingProgress: Double {
        if appState.sessionState == .active {
            return animatedProgress
        }
        return isCountingDown ? countdownProgress : 1
    }

    /// Returns the primary ring text for the current home-screen state.
    private var heroRingCenterText: String {
        if appState.sessionState == .active {
            return animatedCenterText
        }
        return isCountingDown ? "\(countdownValue ?? 3)" : String(localized: "Ready?")
    }

    /// Returns the supporting ring label for the current home-screen state.
    private var heroRingSubtitle: String {
        if appState.sessionState == .active {
            return animatedRingSubtitle
        }
        return isCountingDown ? String(localized: "Starting...") : String(localized: "Tap to Start")
    }

    /// Returns the ring color for the current home-screen state.
    private var heroRingColor: Color {
        if appState.sessionState == .active {
            return AppColors.accent
        }
        return isCountingDown ? AppColors.accent : AppColors.textMuted
    }

    /// Returns a VoiceOver label for the current hero-ring state.
    private var heroRingAccessibilityLabel: String {
        if appState.sessionState == .active {
            return activeRingAccessibilityLabel
        }
        return isCountingDown ? String(localized: "Workout countdown") : String(localized: "Ready to start workout")
    }

    /// Returns the current ring state in a short form for accessibility.
    private var heroRingAccessibilityValue: String {
        if appState.sessionState == .active {
            return activeRingAccessibilityValue
        }
        if let countdownValue {
            return String(
                format: String(localized: "%lld seconds remaining"),
                Int64(countdownValue)
            )
        }
        return goalText
    }

    /// Builds the hero ring for the current state.
    private var heroRingView: some View {
        HeroRingView(
            progress: heroRingProgress,
            color: heroRingColor,
            centerText: heroRingCenterText,
            subtitle: heroRingSubtitle,
            accessibilityLabel: heroRingAccessibilityLabel,
            accessibilityValue: heroRingAccessibilityValue
        )
        .contentShape(Circle())
        .onTapGesture {
            guard appState.sessionState != .active else { return }
            if isCountingDown {
                cancelCountdown()
            } else {
                startWithCountdown()
            }
        }
        .accessibilityAddTraits(appState.sessionState == .active ? [] : .isButton)
        .accessibilityHint(appState.sessionState == .active ? "" : String(localized: "Tap to start or cancel workout countdown."))
    }

    // MARK: - View Body

    /// Renders the home screen, transitioning in-place between idle readiness, countdown, and active tracking.
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Fixed top spacer clamps Hero Ring at a constant offset from top navigation bar
                Spacer(minLength: 8)
                    .frame(maxHeight: 28)

                // Hero Ring remains centered in-place across all session states without shifting
                heroRingView

                // Flexible spacer absorbs bottom safe area / tab bar transitions below the ring
                Spacer(minLength: 16)

                // Dynamic bottom controls housed in a fixed-height container so statistics slide in below the ring
                Group {
                    if appState.sessionState == .active {
                        activeSessionMetricsAndControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        idleControls
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(height: 270, alignment: .bottom)
                .clipped()
                .animation(.spring(duration: 0.4, bounce: 0.15), value: appState.sessionState)
            }
            .padding(.horizontal, 24)
            .toolbarVisibility(appState.sessionState == .idle ? .visible : .hidden, for: .tabBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 2) {
                        ZStack {
                            Text("JumpRec")
                                .font(AppFonts.screenTitle)
                                .foregroundStyle(AppColors.textPrimary)
                                .offset(x: appState.sessionState == .active ? -18 : 0)

                            if appState.sessionState == .active {
                                deviceSourceBadge
                                    .offset(x: 54)
                                    .transition(.opacity)
                            }
                        }
                        .animation(.easeOut(duration: 0.5), value: appState.sessionState)

                        HStack(spacing: 4) {
                            Image(systemName: "target")
                            Text(appState.sessionState == .active ? activeGoalText : goalText)
                                .lineLimit(1)
                                .contentTransition(.numericText())
                        }
                        .font(AppFonts.heroRingSubtitle)
                        .foregroundStyle(AppColors.accent)
                        .fixedSize(horizontal: true, vertical: false)
                        .animation(.spring(duration: 0.4, bounce: 0.2), value: appState.sessionState)
                    }
                    .accessibilityElement(children: .combine)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettingsView = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .tint(.primary)
                    .matchedTransitionSource(id: Self.settingsTransitionID, in: navigationTransitionNamespace)
                    .disabled(isCountingDown)
                }
            }
            .sheet(isPresented: $showSettingsView) {
                SettingsView(settings: settings)
                    .navigationTransition(.zoom(sourceID: Self.settingsTransitionID, in: navigationTransitionNamespace))
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .presentationBackground(AppColors.cardSurface)
                    .presentationContentInteraction(.scrolls)
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .task(id: appState.sessionState) {
                guard appState.sessionState == .active else { return }
                syncHeroRing(animated: true)
                while !Task.isCancelled, appState.sessionState == .active {
                    now = Date()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            .onChange(of: appState.jumpCount) {
                if appState.sessionState == .active {
                    syncHeroRing()
                }
            }
            .onChange(of: appState.sessionGoalValue) {
                if appState.sessionState == .active {
                    syncHeroRing()
                }
            }
            .onChange(of: appState.sessionGoalType) {
                if appState.sessionState == .active {
                    syncHeroRing()
                }
            }
            .onChange(of: now) {
                if appState.sessionState == .active, goalType == .time {
                    syncHeroRing()
                }
            }
            .onDisappear {
                countdownTask?.cancel()
                countdownTask = nil
                countdownValue = nil
            }
        }
    }

    // MARK: - Private Subviews

    /// Returns whether the user is permitted to start a new workout.
    /// Unlimited workouts are available if the user has completed fewer than 100
    /// qualified sessions or has unlocked the one-time license.
    private var canStartWorkout: Bool {
        dataStore.canStartNewWorkout(isLicenseUnlocked: purchaseManager.hasUnlockedUnlimitedWorkouts)
    }

    /// Renders the start/cancel button when the session is idle or counting down.
    private var idleControls: some View {
        Button {
            if isCountingDown {
                cancelCountdown()
            } else {
                if !canStartWorkout {
                    showPaywall = true
                } else {
                    startWithCountdown()
                }
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
        .padding(.bottom, 24)
    }

    /// Renders live active workout metrics and the stop slider.
    private var activeSessionMetricsAndControls: some View {
        VStack(spacing: 20) {
            LazyVGrid(columns: statColumns, spacing: 10) {
                StatCardView(label: leadingStatLabel, value: leadingStatValue)
                StatCardView(label: "CALORIES", value: "\(Int(appState.caloriesBurned.rounded()))")
                StatCardView(label: "HR", value: heartRateText, valueColor: AppColors.accent)
                StatCardView(label: "RATE(AVG)", value: localizedRateText(appState.averageRate))
            }

            GlassSlider(
                text: stopSliderText,
                iconName: "stop.fill",
                config: GlassSlider.Config(tint: stopSliderTint, size: 80),
                onProgressChanged: { _ in },
                onFinished: {
                    onStop()
                }
            )
            .accessibilityLabel(Text(stopSliderText))
            .accessibilityHint(Text(stopSliderAccessibilityHint))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction {
                onStop()
            }
        }
        .padding(.bottom, 16)
    }

    /// Shows the active motion source as an icon-only badge in the header.
    private var deviceSourceBadge: some View {
        Image(systemName: deviceSourceIconName)
            .font(AppFonts.bodySmall)
            .foregroundStyle(AppColors.accent)
            .frame(width: 24, height: 24)
            .background(AppColors.cardSurface)
            .overlay {
                Circle()
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
            }
            .clipShape(Circle())
            .accessibilityLabel(deviceSourceAccessibilityLabel)
    }

    // MARK: - Helpers

    /// Starts the animated pre-session countdown.
    private func startWithCountdown() {
        guard !isCountingDown, !isStartingSession else { return }

        countdownTask = Task {
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.35)) {
                    countdownValue = 3
                    countdownProgress = 1
                }
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
                    withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                        countdownValue = value
                    }
                }
                try? await Task.sleep(for: .seconds(1))
            }

            if Task.isCancelled { return }
            await MainActor.run {
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
                    countdownValue = nil
                    countdownProgress = 1
                    countdownTask = nil
                    onStart()
                }
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

    /// Synchronizes the displayed hero-ring values with the latest active session state.
    private func syncHeroRing(animated: Bool = true) {
        guard appState.sessionState == .active else { return }
        let updates = {
            animatedProgress = activeProgress
            animatedCenterText = activeRingCenterText
            animatedRingSubtitle = activeRingSubtitle
        }

        if animated {
            withAnimation(.spring(duration: 0.4, bounce: 0.2)) {
                updates()
            }
        } else {
            updates()
        }
    }
}

#Preview("Idle") {
    HomeView(
        settings: JumpRecSettings(),
        appState: JumpRecState(),
        onStart: {},
        onStop: {}
    )
    .environment(MyDataStore.shared)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
