//
//  SessionMetricsSummaryView.swift
//  JumpRec
//

import SwiftUI

/// Displays the full metrics summary for a completed session.
struct SessionMetricsSummaryView: View {
    /// The formatted session duration.
    let duration: String
    /// The formatted jump count.
    let jumps: String
    /// The formatted calories value.
    let calories: String
    /// The formatted average jump rate.
    let averageRate: String
    /// The formatted peak jump rate.
    let peakRate: String
    /// The formatted rhythm-consistency score.
    let rhythmConsistency: String
    /// The formatted calorie-efficiency value.
    let caloriesPerMinute: String
    /// The formatted longest streak value.
    let longestJumpStrikes: String
    /// The formatted short-break count.
    let shortBreaks: String
    /// The formatted long-break count.
    let longBreaks: String
    /// The formatted average heart-rate value.
    let averageHeartRate: String
    /// The formatted peak heart-rate value.
    let peakHeartRate: String
    /// The rate samples plotted in the chart.
    let rateSamples: [SessionRateSample]
    /// The record kinds newly achieved in the current context.
    let achievedRecordKinds: [PersonalRecordKind]

    /// Explains why heart-rate data can be unavailable for some sessions.
    private let heartRateExplanation = SessionBreakdownExplanation(
        id: "heart-rate-availability",
        title: "Heart Rate Availability",
        message: "Heart rate is only available when your session is recorded with Apple Watch or supported headphones that provide heart-rate data."
    )

    // MARK: - View

    /// Renders the stats grid, rate chart, and breakdown rows.
    var body: some View {
        VStack(spacing: 20) {
            // Stats Grid
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    SessionMetricCard(
                        label: "DURATION",
                        value: duration,
                        showsBadge: achievedRecordKinds.contains(.longestSession)
                    )
                    SessionMetricCard(
                        label: "JUMPS",
                        value: jumps,
                        showsBadge: achievedRecordKinds.contains(.highestJumpCount)
                    )
                }

                HStack(spacing: 10) {
                    SessionMetricCard(
                        label: "CALORIES",
                        value: calories,
                        showsBadge: achievedRecordKinds.contains(.mostCalories)
                    )
                    SessionMetricCard(
                        label: "AVG RATE",
                        value: averageRate,
                        showsBadge: achievedRecordKinds.contains(.bestAverageJumpRate)
                    )
                }
            }

            // Graph Section
            VStack(alignment: .leading, spacing: 12) {
                Text("JUMPING RATE")
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                JumpingRateGraphView(
                    samples: rateSamples
                )
                .frame(height: 160)
            }
            .padding(16)
            .background(AppColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Session Breakdown
            VStack(alignment: .leading, spacing: 8) {
                Text("SESSION BREAKDOWN")
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                SessionBreakdownRow(
                    label: "Peak Rate",
                    showsBadge: achievedRecordKinds.contains(.bestJumpRate)
                ) {
                    Text(peakRate)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Calories Per Minute",
                    explanation: SessionBreakdownExplanation(
                        id: "calories-per-minute",
                        title: "Calories Per Minute",
                        message: "Your average calorie burn efficiency across the full session duration."
                    ),
                    showsBadge: achievedRecordKinds.contains(.sneakyBurn)
                ) {
                    Text(caloriesPerMinute)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Rhythm Consistency",
                    explanation: SessionBreakdownExplanation(
                        id: "rhythm-consistency",
                        title: "Rhythm Consistency",
                        message: "A normalized score that reflects how evenly you maintained your jumping pace throughout the session."
                    ),
                    showsBadge: achievedRecordKinds.contains(.steadyRhythm)
                ) {
                    Text(rhythmConsistency)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Longest Jump Strikes",
                    explanation: SessionBreakdownExplanation(
                        id: "longest-streak",
                        title: "Longest Streak",
                        message: "The highest number of consecutive jumps you completed without stopping."
                    ),
                    showsBadge: achievedRecordKinds.contains(.longestJumpStreak)
                ) {
                    Text(longestJumpStrikes)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Short Breaks",
                    explanation: SessionBreakdownExplanation(
                        id: "short-breaks",
                        title: "Short Breaks",
                        message: "The number of detected pauses longer than 5 seconds and up to 15 seconds between jumps."
                    )
                ) {
                    Text(shortBreaks)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Long Breaks",
                    explanation: SessionBreakdownExplanation(
                        id: "long-breaks",
                        title: "Long Breaks",
                        message: "The number of detected pauses longer than 15 seconds between jumps."
                    )
                ) {
                    Text(longBreaks)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Average Heart Rate",
                    explanation: heartRateExplanation
                ) {
                    Text(averageHeartRate)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }

                SessionBreakdownRow(
                    label: "Peak Heart Rate",
                    explanation: heartRateExplanation
                ) {
                    Text(peakHeartRate)
                        .font(AppFonts.metricDetailMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }
        }
    }
}
