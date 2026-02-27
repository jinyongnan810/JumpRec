//
//  ActiveSessionView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct ActiveSessionView: View {
    var settings: JumpRecSettings
    var onStop: () -> Void

    // Placeholder values for UI-only implementation
    @State private var jumpCount: Int = 432
    @State private var elapsedSeconds: Int = 272 // 04:32
    @State private var calories: Int = 86
    @State private var rate: Int = 128
    @State private var smallBreaks: Int = 2
    @State private var longBreaks: Int = 0
    @State private var heartRateAvg: Int = 78
    @State private var heartRateCurrent: Int = 96

    private var goalValue: Int64 {
        settings.goalType == .count ? settings.jumpCount : settings.jumpTime
    }

    private var progress: Double {
        guard goalValue > 0 else { return 0 }
        if settings.goalType == .count {
            return min(1.0, Double(jumpCount) / Double(goalValue))
        } else {
            let goalSeconds = goalValue * 60
            return min(1.0, Double(elapsedSeconds) / Double(goalSeconds))
        }
    }

    private var goalText: String {
        if settings.goalType == .count {
            "Goal: \(settings.jumpCount.formatted()) jumps"
        } else {
            "Goal: \(settings.jumpTime) min"
        }
    }

    private var ringSubtitle: String {
        if settings.goalType == .count {
            "/ \(settings.jumpCount.formatted()) jumps"
        } else {
            "/ \(settings.jumpTime) min"
        }
    }

    private var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    var body: some View {
        VStack(spacing: 28) {
            // Header
            VStack(spacing: 4) {
                Text("JumpRec")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Label(goalText, systemImage: "target")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.accent)
            }

            // Hero Ring with progress
            HeroRingView(
                progress: progress,
                centerText: "\(jumpCount)",
                subtitle: ringSubtitle
            )

            // Device Selector (locked during session)
            DeviceSelectorView()

            // Stats Row 1: TIME, CALORIES, RATE
            HStack(spacing: 10) {
                StatCardView(label: "TIME", value: elapsedFormatted)
                StatCardView(label: "CALORIES", value: "\(calories)")
                StatCardView(label: "RATE", value: "\(rate)/m", valueColor: AppColors.accent)
            }

            // Stats Row 2: BREAKS, HEART RATE
            HStack(spacing: 10) {
                StatCardView(
                    label: "BREAKS",
                    value: "\(smallBreaks)/\(longBreaks)",
                    valueColor: AppColors.warning
                )
                StatCardView(
                    label: "HEART RATE",
                    value: "\(heartRateAvg)/\(heartRateCurrent)",
                    valueColor: AppColors.heartRate
                )
            }

            Spacer()

            // Stop Button
            Button(action: onStop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                    Text("STOP SESSION")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.danger)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 24)
    }
}
