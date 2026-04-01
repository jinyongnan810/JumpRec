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

    // MARK: - View

    /// Renders the compact stat card.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFonts.eyebrowLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(AppFonts.metricValueMonospaced)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HStack(spacing: 10) {
        StatCardView(label: "TIME", value: "04:32")
        StatCardView(label: "CALORIES", value: "86")
        StatCardView(label: "RATE", value: "128/m", valueColor: AppColors.accent)
    }
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
