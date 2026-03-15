//
//  HeroRingView.swift
//  JumpRec
//

import SwiftUI

/// Displays the large circular progress ring used on the home and active-session screens.
struct HeroRingView: View {
    /// The normalized progress value from `0.0` to `1.0`.
    var progress: Double
    /// The primary text shown in the center of the ring.
    var centerText: String
    /// The supporting label shown below the center text.
    var subtitle: String

    // MARK: - View

    /// Renders the ring, progress stroke, and center content.
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(AppColors.cardSurface, lineWidth: 14)
                .frame(width: 200, height: 200)

            // Foreground ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(-90))

            // Center content
            VStack(spacing: 4) {
                Text(centerText)
                    .font(.system(size: 48, weight: .bold, design: .rounded))
                    .foregroundStyle(AppColors.accent)
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
    }
}

#Preview("Ready State") {
    HeroRingView(progress: 0, centerText: "Ready", subtitle: "Tap Start to begin")
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}

#Preview("In Progress") {
    HeroRingView(progress: 0.65, centerText: "432", subtitle: "/ 1,000 jumps")
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
