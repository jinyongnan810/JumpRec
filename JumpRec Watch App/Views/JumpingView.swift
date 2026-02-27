//
//  JumpingView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import JumpRecShared
import SwiftUI

struct JumpingView: View {
    @Binding var appState: JumpRecState
    var body: some View {
        VStack(spacing: 4) {
            Text("JUMPS")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text("\(appState.jumpCount)")
                .font(.system(size: 40, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColors.accent)

            Spacer()

            HStack {
                TimerView(startTime: appState.startTime ?? Date())
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)

                Spacer()

                HStack(spacing: 4) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 10))
                    Text(appState.heartrate == 0 ? "--" : "\(appState.heartrate)")
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                }
                .foregroundStyle(AppColors.heartRate)
            }

            // Stop button
            Button {
                appState.end()
            } label: {
                Text("STOP")
                    .font(.system(size: 12, weight: .bold, design: .monospaced))
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
    JumpingView(appState: .constant(JumpRecState()))
}
