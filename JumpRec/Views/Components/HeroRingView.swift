//
//  HeroRingView.swift
//  JumpRec
//

import SwiftUI

/// Displays the large circular progress ring used on the home and active-session screens.
struct HeroRingView: View {
    /// The normalized progress value from `0.0` to `1.0`.
    var progress: Double
    /// The color used by the progress ring.
    var color: Color = AppColors.accent
    /// The primary text shown in the center of the ring.
    var centerText: String
    /// The supporting label shown below the center text.
    var subtitle: String
    /// Supporting diameter in points.
    var diameter: CGFloat = 270
    /// Stroke width in points.
    var lineWidth: CGFloat = 18
    /// Optional VoiceOver label for screens where the ring's visual text needs more context.
    var accessibilityLabel: String?
    /// Optional VoiceOver value for the ring's current progress or state.
    var accessibilityValue: String?

    // MARK: - View

    /// Renders the ring, progress stroke, and center content.
    var body: some View {
        ZStack {
            // Background ring
            Circle()
                .stroke(AppColors.cardSurface, lineWidth: lineWidth)
                .frame(width: diameter, height: diameter)
                .accessibilityHidden(true)

            // Foreground ring
            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .frame(width: diameter, height: diameter)
                .rotationEffect(.degrees(-90))
                .accessibilityHidden(true)

            // Center content
            VStack(spacing: 6) {
                Text(centerText)
                    .font(AppFonts.heroRingValue)
                    .foregroundStyle(AppColors.accent)
                    .contentTransition(.numericText())

                Text(subtitle)
                    .font(AppFonts.heroRingSubtitle)
                    .foregroundStyle(AppColors.textSecondary)
                    .contentTransition(.opacity)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel ?? centerText)
        .accessibilityValue(accessibilityValue ?? subtitle)
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
