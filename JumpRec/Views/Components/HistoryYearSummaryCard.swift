//
//  HistoryYearSummaryCard.swift
//  JumpRec
//

import SwiftUI

/// Displays the year header card used in the annual history tab.
/// Matches the visual styling, padding, and chevron controls of `HistoryCalendarView`.
struct HistoryYearSummaryCard: View {
    /// The numeric year being displayed (e.g. 2026).
    let year: Int
    /// Total jump count for the year.
    let totalJumps: Int
    /// Total number of workouts recorded in the year.
    let workoutCount: Int
    /// Action triggered when navigating to the previous year.
    let onPreviousYear: () -> Void
    /// Action triggered when navigating to the next year.
    let onNextYear: () -> Void

    /// Minimum horizontal translation required to trigger a swipe navigation between years.
    private let swipeThreshold: CGFloat = 50

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button(action: onPreviousYear) {
                    Image(systemName: "chevron.left")
                        .font(AppFonts.sectionIcon)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text(String(localized: "Previous year")))
                .accessibilityHint(Text(String(localized: "Shows the previous year of workouts.")))

                Spacer()

                // Render verbatim unformatted string so "2026" is never displayed with grouping commas (e.g. "2,026").
                Text(verbatim: String(year))
                    .font(AppFonts.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button(action: onNextYear) {
                    Image(systemName: "chevron.right")
                        .font(AppFonts.sectionIcon)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)
                .accessibilityLabel(Text(String(localized: "Next year")))
                .accessibilityHint(Text(String(localized: "Shows the next year of workouts.")))
            }

            VStack(spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(formattedJumps)
                        .font(AppFonts.metricValueXLMonospaced)
                        .foregroundStyle(AppColors.accent)

                    Text(String(localized: "JUMPS"))
                        .font(AppFonts.eyebrowLabel)
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)
                }

                Text(subtitleText)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
        }
        .padding(16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height

                    guard abs(horizontal) > abs(vertical), abs(horizontal) > swipeThreshold else { return }

                    if horizontal < 0 {
                        onNextYear()
                    } else {
                        onPreviousYear()
                    }
                }
        )
    }

    /// Formats the jump count for the large card display (e.g. "142.8K" or "840").
    private var formattedJumps: String {
        if totalJumps >= 10000 {
            return String(format: "%.1fK", Double(totalJumps) / 1000.0)
        }
        return totalJumps.formatted()
    }

    /// Formats the workout subtitle with an ungrouped integer year, such as 2026.
    private var subtitleText: String {
        String(
            format: String(localized: "%lld workouts in %d"),
            Int64(workoutCount),
            year
        )
    }
}

// MARK: - Preview

#Preview("Populated Year") {
    HistoryYearSummaryCard(
        year: 2026,
        totalJumps: 142_800,
        workoutCount: 186,
        onPreviousYear: {},
        onNextYear: {}
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Empty Year") {
    HistoryYearSummaryCard(
        year: 2026,
        totalJumps: 0,
        workoutCount: 0,
        onPreviousYear: {},
        onNextYear: {}
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
