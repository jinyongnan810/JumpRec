//
//  HistoryCalendarView.swift
//  JumpRec
//

import SwiftUI

struct HistoryCalendarView: View {
    let displayedMonth: Date
    let sessionDays: Set<Int>
    let jumpsByDay: [Int: Int]
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void

    private var calendar: Calendar { Calendar.current }

    private var year: Int { calendar.component(.year, from: displayedMonth) }
    private var month: Int { calendar.component(.month, from: displayedMonth) }

    /// Day of week the month starts on (1 = Sunday)
    private var firstWeekday: Int {
        let comps = DateComponents(year: year, month: month, day: 1)
        guard let date = calendar.date(from: comps) else { return 1 }
        return calendar.component(.weekday, from: date)
    }

    /// Number of days in the month
    private var daysInMonth: Int {
        let comps = DateComponents(year: year, month: month)
        guard let date = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: date) else { return 30 }
        return range.count
    }

    /// Today's day number if we're viewing the current month, otherwise nil
    private var todayDay: Int? {
        let now = Date()
        let nowComps = calendar.dateComponents([.year, .month, .day], from: now)
        if nowComps.year == year, nowComps.month == month {
            return nowComps.day
        }
        return nil
    }

    /// Whether a given day is in the future
    private func isFutureDay(_ day: Int) -> Bool {
        guard let todayDay else { return false }
        return day > todayDay
    }

    private let dayHeaders = ["SU", "MO", "TU", "WE", "TH", "FR", "SA"]
    private let swipeThreshold: CGFloat = 50

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button(action: onPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button(action: onNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)
            }

            HStack(spacing: 0) {
                ForEach(dayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(AppColors.tabInactive)
                        .frame(maxWidth: .infinity)
                }
            }

            let offset = firstWeekday - 1
            let totalCells = offset + daysInMonth
            let rows = (totalCells + 6) / 7

            VStack(spacing: 4) {
                ForEach(0 ..< rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let day = cellIndex - offset + 1

                            if day >= 1, day <= daysInMonth {
                                HistoryCalendarDayCellView(
                                    day: day,
                                    hasSession: sessionDays.contains(day),
                                    jumpCount: jumpsByDay[day],
                                    isToday: todayDay == day,
                                    isFuture: isFutureDay(day)
                                )
                                .frame(maxWidth: .infinity)
                            } else {
                                Color.clear
                                    .frame(width: 36, height: 48)
                                    .frame(maxWidth: .infinity)
                            }
                        }
                    }
                }
            }
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
                        onNextMonth()
                    } else {
                        onPreviousMonth()
                    }
                }
        )
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMM")
        return formatter.string(from: displayedMonth)
    }
}

private struct HistoryCalendarDayCellView: View {
    let day: Int
    let hasSession: Bool
    let jumpCount: Int?
    let isToday: Bool
    let isFuture: Bool

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                if hasSession, !isToday {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 36, height: 36)
                } else if isToday {
                    Circle()
                        .fill(Color(hex: 0x0F172A))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Circle()
                                .stroke(AppColors.accent, lineWidth: 2)
                        )
                }

                Text("\(day)")
                    .font(.system(size: 12, weight: dayFontWeight, design: .monospaced))
                    .foregroundStyle(dayColor)
            }
            .frame(width: 36, height: 36)

            if let jumpCount {
                Text(formatJumpCount(jumpCount))
                    .font(.system(size: 8, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColors.accent)
            }
        }
        .frame(height: 48)
    }

    private func formatJumpCount(_ count: Int) -> String {
        if count >= 1000 {
            return String(format: "%.1fK", Double(count) / 1000.0)
        }
        return "\(count)"
    }

    private var dayColor: Color {
        if hasSession, !isToday {
            AppColors.bgPrimary
        } else if isToday {
            AppColors.accent
        } else if isFuture {
            AppColors.tabInactive
        } else {
            AppColors.textSecondary
        }
    }

    private var dayFontWeight: Font.Weight {
        if hasSession || isToday {
            return .semibold
        }
        return .medium
    }
}
