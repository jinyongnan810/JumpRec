//
//  StartView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/10/05.
//

import HealthKit
import OSLog
import SwiftUI

/// Displays the watch start screen and pre-session countdown.
struct StartView: View {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "JumpRec.watch", category: "Permissions")

    /// Holds the shared watch app state driving preparation and countdown transitions.
    @Bindable var appState: JumpRecState

    /// Drives the countdown ring trim animation from the current countdown second.
    @State private var countdownTrim: Double = 1.0

    /// Provides the currently selected workout goal.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    /// Controls navigation to the goal settings screen.
    @State var showSettings: Bool = false

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
                if appState.isCountingDown {
                    ZStack {
                        Text(appState.countdown.formatted())
                            .font(AppFonts.monospaced(displaySize, weight: .bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .foregroundStyle(AppColors.textPrimary)
                            .contentTransition(.numericText())
                            .animation(.default, value: appState.countdown)
                        Circle()
                            .trim(from: 0, to: countdownTrim)
                            .stroke(
                                style: .init(
                                    lineWidth: 8,
                                    lineCap: .round
                                )
                            )
                            .foregroundStyle(AppColors.accent)
                            .rotationEffect(.degrees(-90))
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Workout countdown"))
                    .accessibilityValue(
                        Text(
                            String(
                                format: String(localized: "%lld seconds remaining"),
                                Int64(appState.countdown)
                            )
                        )
                    )
                    .task {
                        let remaining = max(1, min(3, appState.countdown))
                        countdownTrim = Double(remaining) / 3.0
                        await Task.yield()
                        guard !Task.isCancelled else { return }
                        withAnimation(.linear(duration: Double(remaining))) {
                            countdownTrim = 0
                        }
                    }
                } else if appState.showQuotaExplanation {
                    quotaReachedExplanation
                } else {
                    VStack(spacing: 12) {
                        Button {
                            appState.requestStart(settings: settings)
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
                        .disabled(appState.isPreparingWorkout)
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
                    .disabled(appState.isPreparingWorkout || appState.isCountingDown)
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .alert("Workout Permissions", isPresented: $appState.showPermissionError) {
                Button("Settings") { showSettings = true }
                Button("OK", role: .cancel) {}
            } message: {
                Text(appState.permissionErrorMessage)
            }
            .onChange(of: appState.isPreparingWorkout || appState.isCountingDown) { _, isStarting in
                if isStarting {
                    showSettings = false
                }
            }
            .task {
                await requestInitialHealthPermissionsIfNeeded()
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
                appState.showQuotaExplanation = false
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

    /// Requests HealthKit access once on launch so the multi-step sheet does not interrupt tapping Start.
    private func requestInitialHealthPermissionsIfNeeded() async {
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else { return }
        #if DEBUG && targetEnvironment(simulator)
            guard !ScreenshotFixtures.isEnabled else { return }
        #endif
        guard !JumpRecState.shared.hasRequestedInitialHealthPermissions,
              !appState.isPreparingWorkout,
              !appState.isCountingDown
        else {
            return
        }

        JumpRecState.shared.hasRequestedInitialHealthPermissions = true
        do {
            try await WorkoutPermissions.requestAuthorization(using: HKHealthStore())
        } catch {
            Self.logger.error("Could not request initial Health permissions: \(error.localizedDescription, privacy: .public)")
        }
    }
}

#Preview {
    StartView(appState: JumpRecState())
        .environment(JumpRecSettings())
}
