//
//  SessionMetricsComponents.swift
//  JumpRec
//

import SwiftUI

/// Metadata for an optional breakdown explanation popover.
struct SessionBreakdownExplanation: Identifiable, Equatable {
    /// Stable identifier for popover presentation.
    let id: String
    /// The popover title.
    let title: LocalizedStringKey
    /// The popover body copy.
    let message: LocalizedStringKey
}

/// Displays a labeled value card inside session summary screens.
struct SessionMetricCard: View {
    /// The metric label shown above the value.
    let label: LocalizedStringKey
    /// The formatted metric value.
    let value: String
    /// The accent color applied to the value text.
    var valueColor: Color = AppColors.textPrimary
    /// Indicates whether this metric should show the new-record badge.
    var showsBadge = false

    // MARK: - View

    /// Renders the metric card layout.
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(AppFonts.eyebrowLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(AppFonts.metricValueLargeMonospaced)
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if showsBadge {
                PersonalRecordBadgeView(style: .compact)
                    .offset(x: 6, y: -6)
            }
        }
    }
}

/// Displays a labeled row for detailed session breakdown values.
struct SessionBreakdownRow<Content: View>: View {
    /// The row label shown on the leading side.
    let label: LocalizedStringKey
    /// The trailing custom content for the row.
    @ViewBuilder let content: Content
    /// Optional explanation displayed when the row is tapped.
    let explanation: SessionBreakdownExplanation?
    /// Indicates whether this breakdown row should show the new-record badge.
    let showsBadge: Bool
    /// Controls local popover presentation for rows with explanations.
    @State private var isShowingExplanation = false

    /// Creates a breakdown row with a plain text label.
    init(
        label: LocalizedStringKey,
        explanation: SessionBreakdownExplanation? = nil,
        showsBadge: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.explanation = explanation
        self.showsBadge = showsBadge
        self.content = content()
    }

    // MARK: - View

    /// Renders the breakdown row container.
    var body: some View {
        HStack {
            HStack(spacing: 6) {
                Text(label)
                    .font(AppFonts.secondaryActionLabel)
                    .foregroundStyle(AppColors.textPrimary)

                if explanation != nil {
                    Image(systemName: "info.circle.fill")
                        .font(AppFonts.smallValue)
                        .foregroundStyle(AppColors.textMuted)
                }
            }

            Spacer()

            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(alignment: .topTrailing) {
            if showsBadge {
                PersonalRecordBadgeView(style: .compact)
                    .offset(x: 6, y: -6)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture {
            guard explanation != nil else { return }
            isShowingExplanation = true
        }
        .popover(isPresented: $isShowingExplanation) {
            if let explanation {
                VStack(alignment: .leading, spacing: 10) {
                    Text(explanation.title)
                        .font(AppFonts.detailValue)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(explanation.message)
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: 280, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
        }
    }
}
