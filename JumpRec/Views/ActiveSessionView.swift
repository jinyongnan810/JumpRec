//
//  ActiveSessionView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct ActiveSessionView: View {
    var settings: JumpRecSettings
    @Bindable var appState: JumpRecState
    var onStop: () -> Void

    @State private var now = Date()

    private var goalValue: Int64 {
        if let mirroredGoalValue = appState.sessionGoalValue {
            return Int64(mirroredGoalValue)
        }
        return settings.goalType == .count ? settings.jumpCount : settings.jumpTime
    }

    private var goalType: GoalType {
        appState.sessionGoalType ?? settings.goalType
    }

    private var progress: Double {
        guard goalValue > 0 else { return 0 }
        if goalType == .count {
            return min(1.0, Double(appState.jumpCount) / Double(goalValue))
        } else {
            let goalSeconds = goalValue * 60
            return min(1.0, Double(elapsedSeconds) / Double(goalSeconds))
        }
    }

    private var goalText: String {
        if goalType == .count {
            "Goal: \(goalValue.formatted()) jumps"
        } else {
            "Goal: \(goalValue) min"
        }
    }

    private var ringSubtitle: String {
        if goalType == .count {
            "/ \(goalValue.formatted()) jumps"
        } else {
            "/ \(goalValue) min"
        }
    }

    private var elapsedFormatted: String {
        let m = elapsedSeconds / 60
        let s = elapsedSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var elapsedSeconds: Int {
        guard let startTime = appState.startTime else { return 0 }
        return max(0, Int(now.timeIntervalSince(startTime)))
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

            DeviceSelectorView(
                activeSource: appState.activeMotionSource,
                isPhoneMotionAvailable: appState.isPhoneMotionAvailable,
                isHeadphoneMotionAvailable: appState.isHeadphoneMotionAvailable,
                isWatchMotionAvailable: appState.activeMotionSource == .watch || appState.isMirroredWatchSession,
                watchUnavailableReason: "Apple Watch is unavailable for this session."
            )

            // Hero Ring with progress
            HeroRingView(
                progress: progress,
                centerText: "\(appState.jumpCount)",
                subtitle: ringSubtitle
            )

            // Stats Row 1: TIME, CALORIES, RATE
            HStack(spacing: 10) {
                StatCardView(label: "TIME", value: elapsedFormatted)
                StatCardView(label: "CALORIES", value: "\(Int(appState.caloriesBurned.rounded()))")
                StatCardView(label: "RATE", value: "\(appState.averageRate)/m", valueColor: AppColors.accent)
            }

            Spacer()

            // Stop Button
            Button(action: onStop) {
                HStack(spacing: 8) {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 18))
                    Text(appState.isMirroredWatchSession ? "STOP ON WATCH" : "STOP SESSION")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: AppColors.danger)
            .disabled(appState.isMirroredWatchSession)
        }
        .padding(.horizontal, 24)
        .task {
            while !Task.isCancelled, appState.sessionState == .active {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var sourceLabel: String {
        switch appState.activeMotionSource {
        case .airpods:
            DeviceSource.airpods.shortName
        case .iPhone:
            DeviceSource.iPhone.shortName
        case .watch:
            DeviceSource.watch.shortName
        case nil:
            "--"
        }
    }
}

#Preview {
    ActiveSessionView(settings: JumpRecSettings(), appState: JumpRecState(), onStop: {})
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
