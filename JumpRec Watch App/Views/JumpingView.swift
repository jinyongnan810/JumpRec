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
    /// Renders the active workout metrics and stop control.
    var body: some View {
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
    }
}

#Preview {
    JumpingView(appState: JumpRecState())
}
