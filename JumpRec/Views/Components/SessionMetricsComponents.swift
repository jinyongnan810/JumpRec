//
//  SessionMetricsComponents.swift
//  JumpRec
//

import SwiftUI

/// Displays a labeled value card inside session summary screens.
struct SessionMetricCard: View {
    /// The metric label shown above the value.
    let label: LocalizedStringKey
    /// The formatted metric value.
    let value: String
    /// The accent color applied to the value text.
    var valueColor: Color = AppColors.textPrimary

    // MARK: - View

    /// Renders the metric card layout.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

/// Displays a labeled row for detailed session breakdown values.
struct SessionBreakdownRow<Content: View>: View {
    /// The row label shown on the leading side.
    let label: LocalizedStringKey
    /// The trailing custom content for the row.
    @ViewBuilder let content: Content

    // MARK: - View

    /// Renders the breakdown row container.
    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
