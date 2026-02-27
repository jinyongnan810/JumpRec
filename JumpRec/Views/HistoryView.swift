//
//  HistoryView.swift
//  JumpRec
//

import JumpRecShared
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \JumpSession.startedAt, order: .reverse) var sessions: [JumpSession]

    @State private var displayedMonth = Date()
    @State private var showRecords = false

    private var calendar: Calendar { Calendar.current }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    /// Sessions that fall within the currently displayed month
    private var sessionsInMonth: [JumpSession] {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return [] }
        return sessions.filter { $0.startedAt >= start && $0.startedAt < end }
    }

    /// Set of day-of-month integers that have sessions
    private var sessionDays: Set<Int> {
        Set(sessionsInMonth.map { calendar.component(.day, from: $0.startedAt) })
    }

    /// Total jump count per day-of-month
    private var jumpsByDay: [Int: Int] {
        var result: [Int: Int] = [:]
        for session in sessionsInMonth {
            let day = calendar.component(.day, from: session.startedAt)
            result[day, default: 0] += session.jumpCount
        }
        return result
    }

    /// Total jumps for the displayed month
    private var totalJumps: Int {
        sessionsInMonth.reduce(0) { $0 + $1.jumpCount }
    }

    /// Total calories for the displayed month
    private var totalCalories: Double {
        sessionsInMonth.reduce(0) { $0 + $1.caloriesBurned }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Header Row
                HStack {
                    Text("History")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button {
                        showRecords = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "trophy.fill")
                                .font(.system(size: 14))
                            Text("Records")
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(AppColors.accent)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 12)
                        .background(AppColors.cardSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }

                // Calendar Section
                CalendarGridView(
                    displayedMonth: displayedMonth,
                    sessionDays: sessionDays,
                    jumpsByDay: jumpsByDay,
                    onPreviousMonth: {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    },
                    onNextMonth: {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    }
                )

                // Monthly Summary
                HStack(spacing: 12) {
                    StatCardView(label: "SESSIONS", value: "\(sessionsInMonth.count)", valueColor: AppColors.accent)
                    StatCardView(label: "TOTAL JUMPS", value: formatCount(totalJumps))
                    StatCardView(label: "CALORIES", value: formatCount(Int(totalCalories)))
                }

                // Recent Sessions
                VStack(alignment: .leading, spacing: 12) {
                    Text("RECENT SESSIONS")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)

                    if sessions.isEmpty {
                        Text("No sessions yet. Start jumping!")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                    } else {
                        VStack(spacing: 8) {
                            ForEach(sessions.prefix(10), id: \.id) { session in
                                SessionRowView(session: session)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .sheet(isPresented: $showRecords) {
            RecordsSheetView()
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
                .presentationBackground(AppColors.cardSurface)
        }
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 10000 {
            let k = Double(value) / 1000.0
            return String(format: "%.1fK", k)
        }
        return value.formatted()
    }
}

// MARK: - Calendar Grid

private struct CalendarGridView: View {
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

    var body: some View {
        VStack(spacing: 12) {
            // Month navigation
            HStack {
                Button(action: onPreviousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Text(monthTitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button(action: onNextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 18))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            // Day headers
            HStack(spacing: 0) {
                ForEach(dayHeaders, id: \.self) { header in
                    Text(header)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(AppColors.tabInactive)
                        .frame(maxWidth: .infinity)
                }
            }

            // Day grid
            let offset = firstWeekday - 1 // number of blank cells before day 1
            let totalCells = offset + daysInMonth
            let rows = (totalCells + 6) / 7

            VStack(spacing: 4) {
                ForEach(0 ..< rows, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0 ..< 7, id: \.self) { col in
                            let cellIndex = row * 7 + col
                            let day = cellIndex - offset + 1

                            if day >= 1, day <= daysInMonth {
                                DayCellView(
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
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }
}

// MARK: - Day Cell

private struct DayCellView: View {
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

// MARK: - Session Row

private struct SessionRowView: View {
    let session: JumpSession

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return formatter.string(from: session.startedAt)
    }

    private var durationText: String {
        let seconds = Int(session.endedAt.timeIntervalSince(session.startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var caloriesText: String {
        "\(Int(session.caloriesBurned)) cal"
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                HStack(spacing: 12) {
                    Text("\(session.jumpCount.formatted()) jumps")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.accent)

                    Text(durationText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)

                    Text(caloriesText)
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 18))
                .foregroundStyle(AppColors.tabInactive)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JumpSession.self, configurations: config)

    let calendar = Calendar.current
    let now = Date()

    // Sample sessions spread across the current month
    let sampleData: [(daysAgo: Int, jumps: Int, minutes: Int, calories: Double, peakRate: Double)] = [
        (0, 847, 5, 156, 179),
        (3, 1024, 7, 198, 186),
        (5, 632, 4, 112, 165),
        (8, 950, 6, 175, 172),
        (10, 1200, 8, 210, 182),
        (12, 780, 5, 140, 168),
        (15, 500, 3, 95, 155),
    ]

    for data in sampleData {
        let start = calendar.date(byAdding: .day, value: -data.daysAgo, to: now)!
        let end = calendar.date(byAdding: .minute, value: data.minutes, to: start)!
        let session = JumpSession(
            startedAt: start,
            endedAt: end,
            jumpCount: data.jumps,
            peakRate: data.peakRate,
            caloriesBurned: data.calories,
            smallBreaksCount: Int.random(in: 1 ... 4),
            longBreaksCount: Int.random(in: 0 ... 2)
        )
        container.mainContext.insert(session)
    }

    return HistoryView()
        .modelContainer(container)
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
