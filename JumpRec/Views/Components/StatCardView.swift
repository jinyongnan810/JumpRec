//
//  StatCardView.swift
//  JumpRec
//

import SwiftUI

/// Displays a compact stat card used in live session and history summaries.
struct StatCardView: View {
    /// The metric label shown above the value.
    let label: LocalizedStringKey
    /// The formatted metric value.
    let value: String
    /// The color applied to the value text.
    var valueColor: Color = AppColors.textPrimary

    /// System timer text updates elapsed time without invalidating the whole card.
    var timerStart: Date?

    private var valueText: Text {
        if let timerStart { Text(timerStart, style: .timer) } else { Text(value) }
    }

    // MARK: - View

    /// Renders the compact stat card.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFonts.eyebrowLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            valueText
                .font(AppFonts.metricValueMonospaced)
                .foregroundStyle(valueColor)
                // Shrink long values to fit a single line.
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        // Expand vertically to fill the container's height so sibling cards in an HStack always share identical heights.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        // Treat the compact label/value pair as one metric so VoiceOver reads the value with its context.
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    HStack(spacing: 10) {
        StatCardView(label: "TIME", value: "1時間35分")
        StatCardView(label: "CALORIES", value: "86")
        StatCardView(label: "RATE", value: "128/m", valueColor: AppColors.accent)
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
