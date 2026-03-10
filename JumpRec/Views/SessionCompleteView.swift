//
//  SessionCompleteView.swift
//  JumpRec
//

import JumpRecShared
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

    private var rateSamples: [SessionRateSample] {
        let durationSeconds = 5 * 60 + 32
        let session = JumpSession(
            startedAt: .now,
            endedAt: .now.addingTimeInterval(TimeInterval(durationSeconds)),
            jumpCount: jumps,
            peakRate: Double(ratePeak),
            averageRate: Double(rateAvg),
            caloriesBurned: Double(calories),
            smallBreaksCount: smallBreaks,
            longBreaksCount: longBreaks,
            averageHeartRate: heartRateAvg,
            peakHeartRate: heartRatePeak
        )
        let values = [107, 115, 130, 135, 145, 160, 165, 180, 170, 150, 155, 165, 150, 130, 135, 145, 155, 165, 170, 150]
        let step = durationSeconds / max(values.count - 1, 1)

        return values.enumerated().map { index, value in
            SessionRateSample(session: session, secondOffset: index * step, rate: Double(value))
        }
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
                        rateSamples: rateSamples
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
