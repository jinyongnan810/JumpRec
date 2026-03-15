//
//  SessionCompleteView.swift
//  JumpRec
//

import SwiftUI

/// Displays the summary screen after a session finishes.
struct SessionCompleteView: View {
    /// The app state containing the just-completed session details.
    @Bindable var appState: JumpRecState
    /// Resets the flow back to the idle state.
    var onDone: () -> Void

    // MARK: - Derived Values

    /// Returns the saved session object when one is available.
    private var completedSession: JumpSession? {
        appState.completedSession
    }

    /// Returns rate samples for the saved session or generates temporary ones from live data.
    private var rateSamples: [SessionRateSample] {
        if let completedSession {
            return (completedSession.rateSamples ?? []).sorted { $0.secondOffset < $1.secondOffset }
        }

        let durationSeconds = max(appState.durationSeconds, 1)
        let session = JumpSession(
            startedAt: appState.startTime ?? .now,
            endedAt: (appState.startTime ?? .now).addingTimeInterval(TimeInterval(durationSeconds)),
            jumpCount: appState.jumpCount,
            peakRate: 0,
            averageRate: Double(appState.averageRate),
            caloriesBurned: appState.caloriesBurned,
            smallBreaksCount: appState.breakMetrics.small,
            longBreaksCount: appState.breakMetrics.long,
            longestStreak: appState.breakMetrics.longestStreak
        )
        return SessionMetricsCalculator.makeRateSamples(
            for: session,
            jumpOffsets: appState.jumps,
            durationSeconds: durationSeconds
        )
    }

    // MARK: - View

    /// Renders the post-session summary, chart, and actions.
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 64, height: 64)
                        Image(systemName: "checkmark")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(AppColors.bgPrimary)
                    }

                    Text("Session Complete!")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Here are your results.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let completedSession,
                   SessionAICommentGenerator.shouldGenerate(for: completedSession)
                {
                    AICommentCardView(
                        comment: completedSession.aiComment,
                        isLoading: completedSession.aiComment == nil && SessionAICommentGenerator.isAvailable
                    )
                }

                SessionMetricsSummaryView(
                    duration: durationText,
                    jumps: jumpCountText,
                    calories: caloriesText,
                    averageRate: averageRateText,
                    peakRate: peakRateText,
                    longestJumpStrikes: longestStreakText,
                    shortBreaks: shortBreaksText,
                    longBreaks: longBreaksText,
                    averageHeartRate: averageHeartRateText,
                    peakHeartRate: peakHeartRateText,
                    rateSamples: rateSamples
                )
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                if let motionCSVShareURL = appState.motionCSVShareURL {
                    ShareLink(item: motionCSVShareURL) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                            Text("SHARE CSV")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                    }
                    .appGlassButton(prominent: false)
                }

                // Done Button
                Button(action: onDone) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 18))
                        Text("DONE")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundStyle(AppColors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .appGlassButton(
                    prominent: true,
                    tint: AppColors.accent
                )
            }.padding(.horizontal, 24)
        }
    }

    // MARK: - Formatting

    /// Returns the completed session duration text.
    private var durationText: String {
        if let completedSession {
            let minutes = completedSession.durationSeconds / 60
            let seconds = completedSession.durationSeconds % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }
        return appState.elapsedFormatted
    }

    /// Returns the formatted jump-count text.
    private var jumpCountText: String {
        if let completedSession {
            return completedSession.jumpCount.formatted()
        }
        return appState.jumpCount.formatted()
    }

    /// Returns the formatted calories text.
    private var caloriesText: String {
        if let completedSession {
            return "\(Int(completedSession.caloriesBurned.rounded()))"
        }
        return "\(Int(appState.caloriesBurned.rounded()))"
    }

    /// Returns the formatted average-rate text.
    private var averageRateText: String {
        if let averageRate = completedSession?.averageRate {
            return localizedRateText(Int(averageRate.rounded()))
        }
        return localizedRateText(appState.averageRate)
    }

    /// Returns the formatted peak-rate text.
    private var peakRateText: String {
        if let peakRate = completedSession?.peakRate {
            return localizedRateText(Int(peakRate.rounded()))
        }
        if let peakRate = SessionMetricsCalculator.peakRate(from: rateSamples) {
            return localizedRateText(Int(peakRate.rounded()))
        }
        return "--"
    }

    /// Returns the formatted longest-streak text.
    private var longestStreakText: String {
        if let completedSession {
            return completedSession.longestStreak.formatted()
        }
        return appState.breakMetrics.longestStreak.formatted()
    }

    /// Returns the formatted short-break count.
    private var shortBreaksText: String {
        if let completedSession {
            return completedSession.smallBreaksCount.formatted()
        }
        return appState.breakMetrics.small.formatted()
    }

    /// Returns the formatted long-break count.
    private var longBreaksText: String {
        if let completedSession {
            return completedSession.longBreaksCount.formatted()
        }
        return appState.breakMetrics.long.formatted()
    }

    /// Returns the formatted average heart-rate text.
    private var averageHeartRateText: String {
        heartRateText(completedSession?.averageHeartRate ?? appState.averageHeartRate)
    }

    /// Returns the formatted peak heart-rate text.
    private var peakHeartRateText: String {
        heartRateText(completedSession?.peakHeartRate ?? appState.peakHeartRate)
    }

    /// Formats an optional heart-rate value for display.
    private func heartRateText(_ value: Int?) -> String {
        guard let value else { return "--" }
        return "\(value) bpm"
    }
}

#Preview {
    SessionCompleteView(appState: JumpRecState(), onDone: {})
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
