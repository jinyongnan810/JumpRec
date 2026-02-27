//
//  ResultView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import JumpRecShared
import SwiftUI

struct ResultView: View {
    @Binding var appState: JumpRecState

    var body: some View {
        NavigationStack {
            VStack(spacing: 8) {
                Text("SESSION COMPLETE")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                Text("\(appState.jumpCount)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)

                Text("JUMPS")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                Divider()
                    .background(AppColors.textMuted.opacity(0.3))
                    .padding(.vertical, 2)

                HStack(spacing: 16) {
                    VStack(spacing: 2) {
                        Image(systemName: "clock")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.textSecondary)
                        Text(appState.totalTime)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    VStack(spacing: 2) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(AppColors.warning)
                        Text(String(format: "%.0f", appState.energyBurned))
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            + Text(" kcal")
                            .font(.system(size: 9, weight: .medium))
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
    ResultView(appState: .constant(JumpRecState()))
}
