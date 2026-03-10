//
//  SessionMetricsSummaryView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct SessionMetricsSummaryView: View {
    let duration: String
    let jumps: String
    let calories: String
    let averageRate: String
    let peakRate: String
    let longestJumpStrikes: String
    let shortBreaks: String
    let longBreaks: String
    let averageHeartRate: String
    let peakHeartRate: String
    let rateSamples: [SessionRateSample]

    var body: some View {
        VStack(spacing: 20) {
            // Stats Grid
            VStack(spacing: 8) {
                HStack(spacing: 10) {
                    SessionMetricCard(label: "DURATION", value: duration)
                    SessionMetricCard(label: "JUMPS", value: jumps, valueColor: AppColors.accent)
                }

                HStack(spacing: 10) {
                    SessionMetricCard(label: "CALORIES", value: calories)
                    SessionMetricCard(label: "AVG RATE", value: averageRate)
                }
            }

            // Graph Section
            VStack(alignment: .leading, spacing: 12) {
                Text("JUMPING RATE")
                    .font(.system(size: 11, weight: .semibold))
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
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                SessionBreakdownRow(label: "Peak Rate") {
                    Text(peakRate)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }

                SessionBreakdownRow(label: "Longest Jump Strikes") {
                    Text(longestJumpStrikes)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.accent)
                }

                SessionBreakdownRow(label: "Short Breaks") {
                    Text(shortBreaks)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.warning)
                }

                SessionBreakdownRow(label: "Long Breaks") {
                    Text(longBreaks)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.warning)
                }

                SessionBreakdownRow(label: "Average Heart Rate") {
                    Text(averageHeartRate)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.heartRate)
                }

                SessionBreakdownRow(label: "Peak Heart Rate") {
                    Text(peakHeartRate)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundStyle(AppColors.heartRate)
                }
            }
        }
    }
}
