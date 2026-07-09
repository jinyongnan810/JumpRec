//
//  ActiveSessionView.swift
//  JumpRec
//

import SwiftUI

/// Shows live progress, metrics, and controls while a session is running.
struct ActiveSessionView: View {
    /// The persisted app settings used as a fallback for goal display.
    var settings: JumpRecSettings
    /// The observable app state driving live session updates.
    @Bindable var appState: JumpRecState
    /// Stops the current local session.
    var onStop: () -> Void

    // MARK: - View State

    /// Tracks the current time for live elapsed-time updates.
    @State private var now = Date()
    /// Animates the progress ring fill.
    @State private var animatedProgress: Double = 0
    /// Animates the primary ring text.
    @State private var animatedCenterText = "0"
    /// Animates the ring subtitle text.
    @State private var animatedRingSubtitle = ""

    // MARK: - Derived Values

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

    /// Returns normalized progress toward the session goal.
    private var progress: Double {
        guard goalValue > 0 else { return 0 }
        if goalType == .count {
            return min(1.0, Double(appState.jumpCount) / Double(goalValue))
        } else {
            let goalSeconds = goalValue * 60
            return min(1.0, Double(elapsedSeconds) / Double(goalSeconds))
        }
    }

    /// Returns the formatted goal text for the header.
    private var goalText: String {
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

    /// Returns the subtitle shown below the hero-ring value.
    private var ringSubtitle: String {
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

    /// Returns the main value shown in the hero ring.
    private var ringCenterText: String {
        if goalType == .count {
            "\(appState.jumpCount)"
        } else {
            "\(elapsedSeconds / 60)"
        }
    }

    /// Returns a VoiceOver label that names the active progress metric rather than exposing only the large number.
    private var ringAccessibilityLabel: String {
        goalType == .count ? String(localized: "Jump progress") : String(localized: "Time progress")
    }

    /// Returns the current progress in a full sentence so VoiceOver users can hear both current and target values.
    private var ringAccessibilityValue: String {
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

    /// Returns the leading stat label based on the goal type.
    private var leadingStatLabel: LocalizedStringKey {
        goalType == .count ? "TIME" : "JUMPS"
    }

    /// Returns the leading stat value based on the goal type.
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

    /// Returns the live average heart-rate text, or a placeholder until HealthKit delivers samples.
    private var averageHeartRateText: String {
        guard let averageHeartRate = appState.averageHeartRate else { return "--" }
        return "\(averageHeartRate) bpm"
    }

    /// Returns the compact symbol used in the active-session header badge.
    private var deviceSourceIconName: String {
        // The source can be temporarily nil before the first local motion update arrives.
        // A generic sensor symbol keeps the badge stable instead of shifting the title layout.
        appState.activeMotionSource?.iconName ?? "iphone.slash"
    }

    /// Returns a VoiceOver label for the icon-only source badge.
    private var deviceSourceAccessibilityLabel: String {
        if let activeMotionSource = appState.activeMotionSource {
            return String(
                format: String(localized: "Tracking with %@"),
                activeMotionSource.shortName
            )
        }
        return String(localized: "Starting motion tracking")
    }

    /// Keeps the live stat cards in two equal columns so adding health metrics does not squeeze text.
    private var statColumns: [GridItem] {
        [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
    }

    // MARK: - View

    /// Renders the active-session layout and live-updating metrics.
    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text("JumpRec")
                        .font(AppFonts.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    deviceSourceBadge
                }

                Label(goalText, systemImage: "target")
                    .font(AppFonts.heroRingSubtitle)
                    .foregroundStyle(AppColors.accent)
            }

            // Hero Ring with progress
            HeroRingView(
                progress: animatedProgress,
                centerText: animatedCenterText,
                subtitle: animatedRingSubtitle,
                accessibilityLabel: ringAccessibilityLabel,
                accessibilityValue: ringAccessibilityValue
            )

            // Live metrics are a grid instead of a single row because health values can be wider
            // than jump/time values once heart-rate samples start arriving from external sensors.
            LazyVGrid(columns: statColumns, spacing: 10) {
                StatCardView(label: leadingStatLabel, value: leadingStatValue)
                StatCardView(label: "CALORIES", value: "\(Int(appState.caloriesBurned.rounded()))")
                StatCardView(label: "HR(AVG)", value: averageHeartRateText, valueColor: AppColors.accent)
                StatCardView(label: "RATE(AVG)", value: localizedRateText(appState.averageRate))
            }

            Spacer()

            // Stop Button
            Button(action: onStop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(AppFonts.sectionIcon)
                    Text(appState.isMirroredWatchSession ? "STOP ON WATCH" : "STOP SESSION")
                        .font(AppFonts.cardTitle)
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: AppColors.danger)
            .disabled(appState.isMirroredWatchSession)
            .accessibilityHint(appState.isMirroredWatchSession ? Text("Stop the workout from Apple Watch.") : Text("Ends the current jump session."))
        }
        .padding(.horizontal, 24)
        .task {
            syncHeroRing(animated: false)
            while !Task.isCancelled, appState.sessionState == .active {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: appState.jumpCount) {
            syncHeroRing()
        }
        .onChange(of: appState.sessionGoalValue) {
            syncHeroRing()
        }
        .onChange(of: appState.sessionGoalType) {
            syncHeroRing()
        }
        .onChange(of: now) {
            if goalType == .time {
                syncHeroRing()
            }
        }
    }

    // MARK: - Private Subviews

    /// Shows the active motion source as an icon-only badge in the header.
    private var deviceSourceBadge: some View {
        Image(systemName: deviceSourceIconName)
            .font(AppFonts.bodySmall)
            .foregroundStyle(AppColors.accent)
            .frame(width: 28, height: 28)
            .background(AppColors.cardSurface)
            .overlay {
                Circle()
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
            }
            .clipShape(Circle())
            .accessibilityLabel(deviceSourceAccessibilityLabel)
    }

    // MARK: - Helpers

    /// Synchronizes the displayed hero-ring values with the latest session state.
    private func syncHeroRing(animated: Bool = true) {
        let updates = {
            animatedProgress = progress
            animatedCenterText = ringCenterText
            animatedRingSubtitle = ringSubtitle
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

#Preview {
    ActiveSessionView(settings: JumpRecSettings(), appState: JumpRecState(), onStop: {})
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
