//
//  JumpingView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

/// Displays the live jumping screen on Apple Watch.
struct JumpingView: View {
    /// The watch app state providing live workout values.
    let appState: JumpRecState
    /// Provides persisted goal settings.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    /// Controls navigation to settings screen.
    @State private var showSettings: Bool = false

    /// Returns a spoken heart-rate value that distinguishes a missing sample from a real zero.
    private var heartRateAccessibilityValue: String {
        guard appState.heartrate > 0 else {
            return String(localized: "No reading")
        }
        return String(
            format: String(localized: "%lld beats per minute"),
            Int64(appState.heartrate)
        )
    }

    /// Renders the active workout metrics and stop control.
    var body: some View {
        NavigationStack {
            VStack(spacing: 4) {
                Text("JUMPS")
                    .font(AppFonts.watchMetricLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                Text("\(appState.jumpCount)")
                    .font(AppFonts.watchMetricValue)
                    .foregroundStyle(AppColors.accent)
                    .contentTransition(.numericText())
                    .animation(.bouncy, value: appState.jumpCount)
                    .accessibilityLabel(Text("Jumps"))
                    .accessibilityValue(Text(appState.jumpCount.formatted()))

                Spacer()

                HStack {
                    TimerView(startTime: appState.startTime ?? Date())
                        .font(AppFonts.watchMetricDetail)
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    HStack(spacing: 4) {
                        Image(systemName: "heart.fill")
                            .font(AppFonts.watchBodySmall)
                        Text(appState.heartrate == 0 ? "--" : "\(appState.heartrate)")
                            .font(AppFonts.watchMetricDetail)
                    }
                    .foregroundStyle(AppColors.heartRate)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Heart rate"))
                    .accessibilityValue(Text(heartRateAccessibilityValue))
                }

                // Stop button
                Button {
                    appState.end()
                } label: {
                    Text("STOP")
                        .font(AppFonts.watchMetricCompact)
                        .tracking(1)
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(AppColors.danger)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings.toggle()
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .accessibilityLabel(Text("Settings"))
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                SettingsView()
            }
            .onChange(of: showSettings) { _, isShowing in
                if !isShowing {
                    appState.applyActiveSessionSettings(
                        goalType: settings.goalType,
                        goalCount: settings.goalCount,
                        shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
                        shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
                        jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage
                    )
                }
            }
        }
    }
}

#Preview {
    JumpingView(appState: JumpRecState())
        .environment(JumpRecSettings())
}
