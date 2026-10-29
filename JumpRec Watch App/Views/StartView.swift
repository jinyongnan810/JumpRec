//
//  StartView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/10/05.
//

import SwiftUI

/// Displays the watch start screen and pre-session countdown.
struct StartView: View {
    /// Indicates whether the countdown is currently showing.
    @State var isCountingDown: Bool = false
    /// Drives the countdown ring animation.
    @State var isAnimating: Bool = false
    /// Stores the current countdown value.
    @State var countdown = 3
    var isCompanionStartRequested = false
    var onCompanionStartConsumed: () -> Void = {}
    @State private var preparationTask: Task<Void, Never>?
    @State private var isPreparingWorkout = false
    @State private var isCompanionAttempt = false
    @State private var showPermissionError = false
    @State private var permissionErrorMessage = ""
    /// Starts the workout when the countdown finishes.
    var onStart: () -> Void

    /// Provides the currently selected workout goal.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    /// Controls navigation to the goal settings screen.
    @State var showSettings: Bool = false
    /// Controls presentation of the quota reached explanation.
    @State private var showQuotaExplanation: Bool = false

    /// Returns the formatted goal text shown under the start button.
    var goal: Text {
        switch settings.goalType {
        case .count:
            return Text(
                String(
                    format: String(localized: "%@ jumps"),
                    settings.jumpCount.formatted()
                )
            )
        case .time:
            return Text(
                String(
                    format: String(localized: "%lld min"),
                    settings.jumpTime
                )
            )
        @unknown default:
            return Text(
                String(
                    format: String(localized: "%@ jumps"),
                    settings.jumpCount.formatted()
                )
            )
        }
    }

    /// Renders the start screen or active countdown.
    @ScaledMetric(relativeTo: .largeTitle) private var displaySize = AppFonts.watchCountdownBaseSize

    var body: some View {
        NavigationStack {
            ZStack {
                if isCountingDown {
                    ZStack {
                        Text(countdown.formatted())
                            .font(AppFonts.monospaced(displaySize, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(AppColors.textPrimary)
                            .contentTransition(.numericText())
                        Circle()
                            .trim(from: 0, to: isAnimating ? 0 : 1)
                            .stroke(
                                style: .init(
                                    lineWidth: 8,
                                    lineCap: .round
                                )
                            )
                            .foregroundStyle(AppColors.accent)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(
                                duration: 3.0
                            ), value: isAnimating)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Workout countdown"))
                    .accessibilityValue(
                        Text(
                            String(
                                format: String(localized: "%lld seconds remaining"),
                                Int64(countdown)
                            )
                        )
                    )
                    .task {
                        await runCountdown()
                    }
                } else if showQuotaExplanation {
                    quotaReachedExplanation
                } else {
                    VStack(spacing: 12) {
                        Button {
                            prepareWorkout()
                        } label: {
                            Text("START")
                                .font(AppFonts.watchPrimaryButton)
                                .tracking(2)
                                .foregroundStyle(AppColors.accentForeground)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(AppColors.accent)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(isPreparingWorkout)
                        .accessibilityHint(Text("Starts a three second countdown before the workout begins."))

                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(AppFonts.watchSupporting)
                            goal
                                .font(AppFonts.watchGoalLabel)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                        .accessibilityElement(children: .combine)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .disabled(isPreparingWorkout || isCountingDown)
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Workout Permissions", isPresented: $showPermissionError) {
                Button("Settings") { showSettings = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text(permissionErrorMessage)
            }
            .onChange(of: isCompanionStartRequested, initial: true) { _, requested in
                guard requested else { return }
                onCompanionStartConsumed()
                settings.loadSettings()
                guard !isPreparingWorkout, !isCountingDown else { return }
                isCompanionAttempt = true
                prepareWorkout()
            }
            .onDisappear {
                preparationTask?.cancel()
                preparationTask = nil
                isPreparingWorkout = false
                cancelCompanionStartIfNeeded()
            }
        }
    }

    /// Shows quota help inline to avoid system-presentation crashes in Watch previews.
    private var quotaReachedExplanation: some View {
        VStack(spacing: 12) {
            Text("Free Limit Reached")
                .font(AppFonts.watchSectionTitle)
                .multilineTextAlignment(.center)

            Text("You've completed your 10 free workouts. Please consider open JumpRec on your iPhone to unlock unlimited workouts.")
                .font(AppFonts.watchSupporting)
                .multilineTextAlignment(.center)

            Button {
                showQuotaExplanation = false
            } label: {
                Text("OK")
                    .font(AppFonts.watchGoalLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(AppColors.accent)
                    .foregroundStyle(AppColors.accentForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
    }

    /// Asks for access before displaying or animating the countdown.
    private func prepareWorkout() {
        guard !isPreparingWorkout, !isCountingDown else { return }
        guard !settings.isQuotaExceeded else {
            showQuotaExplanation = true
            cancelCompanionStartIfNeeded()
            return
        }
        isPreparingWorkout = true
        preparationTask = Task { @MainActor in
            do {
                try await WorkoutPermissions.prepareForWorkout()
                try Task.checkCancellation()
                isPreparingWorkout = false
                withAnimation { isCountingDown = true }
            } catch {
                guard !Task.isCancelled else { return }
                isPreparingWorkout = false
                permissionErrorMessage = (error as? WorkoutPermissions.PreparationError)?.localizedDescription
                    ?? String(localized: "Unable to prepare workout permissions. Please try again or review access in Settings.")
                showPermissionError = true
                cancelCompanionStartIfNeeded()
            }
        }
    }

    private func cancelCompanionStartIfNeeded() {
        guard isCompanionAttempt else { return }
        isCompanionAttempt = false
        ConnectivityManager.shared.sendMessage(["watch app": "startCancelled"])
    }

    // MARK: - Countdown

    /// Starts a workout after the countdown only while its SwiftUI task remains active.
    private func runCountdown() async {
        countdown = 3
        isAnimating = false

        // Allow SwiftUI to render the full ring before animating its trim to zero.
        await Task.yield()
        guard !Task.isCancelled else { return }

        withAnimation(.linear(duration: 3)) {
            isAnimating = true
        }

        for value in stride(from: 2, through: 1, by: -1) {
            do {
                try await Task.sleep(for: .seconds(1))
            } catch {
                return
            }

            guard !Task.isCancelled else { return }
            withAnimation {
                countdown = value
            }
        }

        do {
            try await Task.sleep(for: .seconds(1))
        } catch {
            return
        }

        guard !Task.isCancelled else { return }
        isCompanionAttempt = false
        onStart()
    }
}

#Preview {
    StartView(onStart: {})
        .environment(JumpRecSettings())
}
