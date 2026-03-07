//
//  SessionCompleteView.swift
//  JumpRec
//

import SwiftUI

struct SessionCompleteView: View {
    var onDone: () -> Void

    // Placeholder session results
    private let duration = "05:32"
    private let jumps = 847
    private let calories = 156
    private let rateAvg = 153
    private let ratePeak = 179
    private let smallBreaks = 3
    private let longBreaks = 1
    private let heartRateAvg = 82
    private let heartRatePeak = 104
    private let longestJumpStrikes = "–"

    // Placeholder graph data points (normalized 0–1 for y-axis range 100–200)
    private let graphPoints: [CGFloat] = [
        0.07, 0.15, 0.30, 0.35, 0.45, 0.60, 0.65, 0.80, 0.70, 0.50,
        0.55, 0.65, 0.50, 0.30, 0.35, 0.45, 0.55, 0.65, 0.70, 0.50,
    ]

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
                        duration: duration,
                        jumps: "\(jumps)",
                        calories: "\(calories)",
                        averageRate: "\(rateAvg)/min",
                        peakRate: "\(ratePeak)/min",
                        longestJumpStrikes: longestJumpStrikes,
                        shortBreaks: "\(smallBreaks)",
                        longBreaks: "\(longBreaks)",
                        averageHeartRate: "\(heartRateAvg)",
                        peakHeartRate: "\(heartRatePeak)",
                        graphPoints: graphPoints,
                        xLabels: ["0:00", "1:23", "2:46", "4:09", "5:32"]
                    )
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)

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
        .padding(.horizontal, 24)
    }
}

#Preview {
    SessionCompleteView(onDone: {})
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
