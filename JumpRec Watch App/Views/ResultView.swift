//
//  ResultView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

/// Displays the watch-side session summary after a workout ends.
struct ResultView: View {
    /// The watch app state containing the finished session values.
    let appState: JumpRecState

    /// Renders the compact results layout.
    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("SESSION COMPLETE")
                    .font(AppFonts.watchMetricLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                Text("\(appState.jumpCount)")
                    .font(AppFonts.watchResultValue)
                    .foregroundStyle(AppColors.accent)

                Text("JUMPS")
                    .font(AppFonts.watchMetricLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                Divider()
                    .background(AppColors.textMuted.opacity(0.3))
                    .padding(.vertical, 2)

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(AppFonts.watchBodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                        Text(appState.totalTime)
                            .font(AppFonts.watchMetricDetailBold)
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(AppFonts.watchBodySmall)
                            .foregroundStyle(AppColors.warning)
                        Text(String(format: "%.0f", appState.energyBurned))
                            .font(AppFonts.watchMetricDetailBold)
                            .foregroundStyle(AppColors.textPrimary)
                            + Text(" kcal")
                            .font(AppFonts.watchBodyTiny)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        appState.reset()
                    } label: {
                        Image(systemName: "xmark")
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
        }
    }
}

#Preview {
    ResultView(appState: JumpRecState())
}
