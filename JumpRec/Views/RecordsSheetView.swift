//
//  RecordsSheetView.swift
//  JumpRec
//

import JumpRecShared
import SwiftData
import SwiftUI

struct RecordsSheetView: View {
    @Query(sort: \JumpSession.startedAt, order: .reverse) var sessions: [JumpSession]
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var records: [RecordItem] {
        guard !sessions.isEmpty else { return [] }

        var items: [RecordItem] = []

        // Highest Jump Count
        if let best = sessions.max(by: { $0.jumpCount < $1.jumpCount }) {
            items.append(RecordItem(
                icon: "trophy.fill",
                label: "Highest Jump Count",
                value: "\(best.jumpCount.formatted()) jumps",
                date: Self.dateFormatter.string(from: best.startedAt)
            ))
        }

        // Longest Session
        if let best = sessions.max(by: {
            $0.endedAt.timeIntervalSince($0.startedAt) < $1.endedAt.timeIntervalSince($1.startedAt)
        }) {
            let seconds = Int(best.endedAt.timeIntervalSince(best.startedAt))
            let m = seconds / 60
            let s = seconds % 60
            items.append(RecordItem(
                icon: "timer",
                label: "Longest Session",
                value: String(format: "%02d:%02d", m, s),
                date: Self.dateFormatter.string(from: best.startedAt)
            ))
        }

        // Most Calories
        if let best = sessions.max(by: { $0.caloriesBurned < $1.caloriesBurned }) {
            items.append(RecordItem(
                icon: "flame.fill",
                label: "Most Calories",
                value: "\(Int(best.caloriesBurned)) cal",
                date: Self.dateFormatter.string(from: best.startedAt)
            ))
        }

        // Best Jump Rate
        if let best = sessions.compactMap({ s -> (JumpSession, Double)? in
            guard let rate = s.peakRate else { return nil }
            return (s, rate)
        }).max(by: { $0.1 < $1.1 }) {
            items.append(RecordItem(
                icon: "bolt.fill",
                label: "Best Jump Rate",
                value: "\(Int(best.1))/min",
                date: Self.dateFormatter.string(from: best.0.startedAt)
            ))
        }

        // Longest Streak
        let streak = computeLongestStreak()
        if streak.days > 0 {
            items.append(RecordItem(
                icon: "calendar.badge.checkmark",
                label: "Longest Streak",
                value: "\(streak.days) days",
                date: streak.dateLabel
            ))
        }

        return items
    }

    var body: some View {
        VStack(spacing: 20) {
            // Drag handle
            RoundedRectangle(cornerRadius: 2)
                .fill(AppColors.tabInactive)
                .frame(width: 40, height: 4)

            // Title
            Text("Personal Records")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            // Records list
            let displayRecords = records
            if displayRecords.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("No records yet")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Complete sessions to set personal records!")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 10) {
                    ForEach(displayRecords) { record in
                        RecordCardView(record: record)
                    }
                }
            }

            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
    }

    // MARK: - Streak calculation

    private func computeLongestStreak() -> (days: Int, dateLabel: String) {
        guard !sessions.isEmpty else { return (0, "") }

        let calendar = Calendar.current

        // Get unique session dates (day granularity), sorted ascending
        let sessionDates: [Date] = Set(sessions.map {
            calendar.startOfDay(for: $0.startedAt)
        }).sorted()

        guard !sessionDates.isEmpty else { return (0, "") }

        var bestStart = sessionDates[0]
        var bestLength = 1
        var currentStart = sessionDates[0]
        var currentLength = 1

        for i in 1 ..< sessionDates.count {
            let prev = sessionDates[i - 1]
            let curr = sessionDates[i]
            let daysBetween = calendar.dateComponents([.day], from: prev, to: curr).day ?? 0

            if daysBetween == 1 {
                currentLength += 1
            } else {
                currentStart = curr
                currentLength = 1
            }

            if currentLength > bestLength {
                bestLength = currentLength
                bestStart = currentStart
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let startLabel = formatter.string(from: bestStart)

        if bestLength == 1 {
            return (1, startLabel)
        }

        guard let endDate = calendar.date(byAdding: .day, value: bestLength - 1, to: bestStart) else {
            return (bestLength, startLabel)
        }
        let endLabel = formatter.string(from: endDate)

        // If same month, compact format like "Feb 1-12"
        let startMonth = calendar.component(.month, from: bestStart)
        let endMonth = calendar.component(.month, from: endDate)
        if startMonth == endMonth {
            let endDay = calendar.component(.day, from: endDate)
            return (bestLength, "\(startLabel)-\(endDay)")
        }

        return (bestLength, "\(startLabel)–\(endLabel)")
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: JumpSession.self, configurations: config)

    let calendar = Calendar.current
    let now = Date()
    let sampleData: [(daysAgo: Int, jumps: Int, minutes: Int, calories: Double, peakRate: Double)] = [
        (3, 2847, 15, 384, 186),
        (10, 1500, 12, 280, 172),
        (20, 900, 6, 150, 155),
    ]
    for data in sampleData {
        let start = calendar.date(byAdding: .day, value: -data.daysAgo, to: now)!
        let end = calendar.date(byAdding: .minute, value: data.minutes, to: start)!
        let session = JumpSession(
            startedAt: start,
            endedAt: end,
            jumpCount: data.jumps,
            peakRate: data.peakRate,
            caloriesBurned: data.calories
        )
        container.mainContext.insert(session)
    }

    return RecordsSheetView()
        .modelContainer(container)
        .presentationBackground(AppColors.cardSurface)
        .preferredColorScheme(.dark)
}

// MARK: - Record Item Model

private struct RecordItem: Identifiable {
    let id = UUID()
    let icon: String
    let label: String
    let value: String
    let date: String
}

// MARK: - Record Card

private struct RecordCardView: View {
    let record: RecordItem

    private static let cardBg = Color(hex: 0x0F172A)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.icon)
                .font(.system(size: 24))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(record.label)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)

                HStack {
                    Text(record.value)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.accent)

                    Spacer()

                    Text(record.date)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
