//
//  SessionCompleteView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct SessionCompleteView: View {
    @Bindable var appState: JumpRecState
    var onDone: () -> Void

    private var rateSamples: [SessionRateSample] {
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

    var body: some View {
        VStack(spacing: 16) {
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

                        Text("Great workout! Here are your results.")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    SessionMetricsSummaryView(
                        duration: appState.elapsedFormatted,
                        jumps: "\(appState.jumpCount)",
                        calories: "\(Int(appState.caloriesBurned.rounded()))",
                        averageRate: "\(appState.averageRate)/min",
                        peakRate: peakRateText,
                        longestJumpStrikes: "\(appState.breakMetrics.longestStreak)",
                        shortBreaks: "\(appState.breakMetrics.small)",
                        longBreaks: "\(appState.breakMetrics.long)",
                        averageHeartRate: heartRateText(appState.averageHeartRate),
                        peakHeartRate: heartRateText(appState.peakHeartRate),
                        rateSamples: rateSamples
                    )
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)

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
                .appGlassButton(prominent: true, tint: AppColors.accent)
            }
        }
        .padding(.horizontal, 24)
    }

    private var peakRateText: String {
        if let peakRate = SessionMetricsCalculator.peakRate(from: rateSamples) {
            return "\(Int(peakRate.rounded()))/min"
        }
        return "--"
    }

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
