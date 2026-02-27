//
//  HeroRingView.swift
//  JumpRec
//

import SwiftUI

struct HeroRingView: View {
    var progress: Double // 0.0 to 1.0
    var centerText: String
    var subtitle: String

    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(AppColors.cardSurface, lineWidth: 8)
                .frame(width: 200, height: 200)

            // Foreground ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 4) {
                Text(centerText)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}
