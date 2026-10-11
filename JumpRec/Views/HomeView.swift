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

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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

    /// Indicates a pending start request, including the Watch handshake.
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

    // MARK: - Unified Hero Ring State Mapping

    /// Builds the hero ring for the current state.
    @ViewBuilder
    private var heroRingView: some View {
        if appState.sessionState == .active {
            ActiveWorkoutRing(appState: appState, settings: settings)
        } else {
            HeroRingView(
                progress: isCountingDown ? countdownProgress : 1,
                color: isCountingDown ? AppColors.accent : AppColors.textMuted,
                centerText: countdownValue.map(String.init) ?? String(localized: "Ready?"),
                subtitle: isCountingDown ? String(localized: "Starting...") : String(localized: "Tap to Start"),
                accessibilityLabel: isCountingDown ? String(localized: "Workout countdown") : String(localized: "Ready to start workout"),
                accessibilityValue: countdownValue.map {
                    String(format: String(localized: "%lld seconds remaining"), Int64($0))
                } ?? goalText
            )
            .contentShape(Circle())
            .onTapGesture {
                if isCountingDown { cancelCountdown() } else { startWithCountdown() }
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint(String(localized: "Tap to start or cancel workout countdown."))
        }
    }

    // MARK: - View Body

    /// Renders the home screen, transitioning in-place between idle readiness, countdown, and active tracking.
    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                // Allow scrolling to reach Stop on small screens and at accessibility text sizes.
                ScrollView {
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
                                ActiveWorkoutControls(appState: appState, settings: settings, onStop: onStop)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            } else {
                                idleControls
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : 270, alignment: .bottom)
                        .animation(.spring(duration: 0.4, bounce: 0.15), value: appState.sessionState)
                    }
                    .padding(.horizontal, 24)
                    .frame(minHeight: geometry.size.height)
                }
                .scrollIndicators(.hidden)
            }
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
            .onDisappear {
                countdownTask?.cancel()
                countdownTask = nil
                countdownValue = nil
            }
        }
    }

    // MARK: - Private Subviews

    /// Allows starting with an unlimited license or fewer than 100 qualifying workouts.
    private var canStartWorkout: Bool {
        dataStore.canStartNewWorkout(isLicenseUnlocked: purchaseManager.hasUnlockedUnlimitedWorkouts)
    }

    /// Renders the start/cancel button when the session is idle or counting down.
    private var idleControls: some View {
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
                // Allow wrapping for larger fonts and longer translations.
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 56)
        }
        .appGlassButton(prominent: true, tint: primaryButtonTint)
        .disabled(isPrimaryButtonDisabled)
        .padding(.bottom, 24)
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

        // Check quota for both ring and button start actions.
        guard canStartWorkout else {
            showPaywall = true
            return
        }

        // Keep countdown state on the main actor and honor cancellation at each suspension.
        countdownTask = Task { @MainActor in
            withAnimation(.easeInOut(duration: 0.35)) {
                countdownValue = 3
                countdownProgress = 1
            }
            // Render the full ring before beginning the three-second trim animation.
            await Task.yield()
            guard !Task.isCancelled else { return }
            withAnimation(.linear(duration: 3)) { countdownProgress = 0 }

            for value in stride(from: 3, through: 1, by: -1) {
                guard !Task.isCancelled else { return }
                withAnimation(.spring(duration: 0.35, bounce: 0.15)) { countdownValue = value }
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    // A cancelled countdown must never invoke its workout start action.
                    return
                }
            }
            guard !Task.isCancelled else { return }
            withAnimation(.spring(duration: 0.35, bounce: 0.15)) {
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

/// Live goal ring; only time goals schedule one-second updates.
private struct ActiveWorkoutRing: View {
    let appState: JumpRecState
    let settings: JumpRecSettings

    var body: some View {
        if (appState.sessionGoalType ?? settings.goalType) == .time {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                ActiveWorkoutRingContent(appState: appState, settings: settings, now: context.date)
            }
        } else {
            ActiveWorkoutRingContent(appState: appState, settings: settings, now: .now)
        }
    }
}

/// Narrow rendering boundary for the metrics that actually change the ring.
private struct ActiveWorkoutRingContent: View {
    let appState: JumpRecState
    let settings: JumpRecSettings
    let now: Date

    var body: some View {
        let type = appState.sessionGoalType ?? settings.goalType
        let goal = appState.sessionGoalValue ?? settings.goalCount
        let elapsed = max(0, Int(now.timeIntervalSince(appState.startTime ?? now)))
        let value = type == .count ? appState.jumpCount : elapsed / 60
        // Convert before multiplying to avoid integer overflow for externally supplied goals.
        let progress = goal > 0 ? min(1, type == .count ? Double(value) / Double(goal) : Double(elapsed) / (Double(goal) * 60)) : 0
        HeroRingView(
            progress: progress,
            centerText: value.formatted(),
            subtitle: type == .count ? String(format: String(localized: "/ %@ jumps"), goal.formatted()) : String(format: String(localized: "/ %lld min"), Int64(goal)),
            accessibilityLabel: type == .count ? String(localized: "Jump progress") : String(localized: "Time progress"),
            accessibilityValue: type == .count ? String(format: String(localized: "%@ of %@ jumps"), value.formatted(), goal.formatted()) : String(format: String(localized: "%lld of %lld minutes"), Int64(value), Int64(goal))
        )
        .animation(.spring(duration: 0.4, bounce: 0.2), value: progress)
    }
}

/// Live metrics with system timer text to keep second updates local to the label.
private struct ActiveWorkoutControls: View {
    let appState: JumpRecState
    let settings: JumpRecSettings
    let onStop: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let isCountGoal = (appState.sessionGoalType ?? settings.goalType) == .count
        VStack(spacing: 20) {
            LazyVGrid(columns: dynamicTypeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                StatCardView(label: isCountGoal ? "TIME" : "JUMPS", value: isCountGoal ? "00:00" : appState.jumpCount.formatted(), timerStart: isCountGoal ? appState.startTime : nil)
                StatCardView(label: "CALORIES", value: "\(Int(appState.caloriesBurned.rounded()))")
                StatCardView(label: "HR", value: appState.heartRate.map { "\($0) bpm" } ?? "--", valueColor: AppColors.accent)
                StatCardView(label: "RATE(AVG)", value: localizedRateText(appState.averageRate))
            }
            GlassSlider(text: String(localized: "STOP WORKOUT"), iconName: "stop.fill", config: .init(tint: AppColors.warning, size: 80), onProgressChanged: { _ in }, onFinished: onStop)
                .accessibilityLabel(Text("STOP WORKOUT"))
                .accessibilityHint(Text("Ends the current jump workout."))
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { onStop() }
        }
        .padding(.bottom, 16)
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
