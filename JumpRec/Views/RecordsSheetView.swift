//
//  RecordsSheetView.swift
//  JumpRec
//

import SwiftData
import SwiftUI

struct RecordsSheetView: View {
    @Query(sort: \PersonalRecord.kindRawValue) private var records: [PersonalRecord]
    @Environment(\.dismiss) private var dismiss

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = .autoupdatingCurrent
        f.setLocalizedDateFormatFromTemplate("yMMMd")
        return f
    }()

    private var displayRecords: [RecordItem] {
        records
            .compactMap { record in
                guard
                    let kindRawValue = record.kindRawValue,
                    let kind = PersonalRecordKind(rawValue: kindRawValue),
                    let metricValue = record.metricValue,
                    let achievedAt = record.achievedAt
                else {
                    return nil
                }

                return RecordItem(
                    kind: kind,
                    metricValue: metricValue,
                    achievedAt: achievedAt
                )
            }
            .sorted { $0.kind.sortOrder < $1.kind.sortOrder }
    }

    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Personal Records")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)

            // Records list
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
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: JumpSession.self,
        PersonalRecord.self,
        SessionRateSample.self,
        configurations: config
    )

    let calendar = Calendar.current
    let now = Date()
    let sampleData: [(daysAgo: Int, jumps: Int, minutes: Int, calories: Double, peakRate: Double, longestStreak: Int)] = [
        (3, 2847, 15, 384, 186, 642),
        (10, 1500, 12, 280, 172, 390),
        (20, 900, 6, 150, 155, 244),
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
            longestStreak: data.longestStreak
        )
        container.mainContext.insert(session)
    }

    container.mainContext.insert(
        PersonalRecord(
            kind: .highestJumpCount,
            metricValue: 2847,
            displayValue: "2,847 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .longestJumpStreak,
            metricValue: 642,
            displayValue: "642 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .longestSession,
            metricValue: 900,
            displayValue: "15:00",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .mostCalories,
            metricValue: 384,
            displayValue: "384 cal",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .bestJumpRate,
            metricValue: 186,
            displayValue: "186/min",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )

    return RecordsSheetView()
        .modelContainer(container)
        .presentationBackground(AppColors.cardSurface)
        .preferredColorScheme(.dark)
}

// MARK: - Record Item Model

private struct RecordItem: Identifiable {
    let id = UUID()
    let kind: PersonalRecordKind
    let metricValue: Double
    let achievedAt: Date
}

// MARK: - Record Card

private struct RecordCardView: View {
    let record: RecordItem

    private static let cardBg = Color(hex: 0x0F172A)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .font(.system(size: 24))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(record.kind.title))
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textPrimary)

                HStack {
                    Text(displayValue)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColors.accent)

                    Spacer()

                    Text(Self.dateFormatter.string(from: record.achievedAt))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    private var displayValue: String {
        switch record.kind {
        case .highestJumpCount:
            return String(
                format: String(localized: "%@ jumps"),
                Int(record.metricValue.rounded()).formatted()
            )
        case .longestJumpStreak:
            return String(
                format: String(localized: "%@ jumps"),
                Int(record.metricValue.rounded()).formatted()
            )
        case .longestSession:
            return formattedDuration(seconds: Int(record.metricValue.rounded()))
        case .mostCalories:
            return "\(Int(record.metricValue.rounded())) \(String(localized: "cal"))"
        case .bestJumpRate:
            return localizedRateText(Int(record.metricValue.rounded()))
        @unknown default:
            return record.metricValue.formatted()
        }
    }

    private func formattedDuration(seconds: Int) -> String {
        let minutes = max(seconds, 0) / 60
        let remainingSeconds = max(seconds, 0) % 60
        return String(format: "%02d:%02d", minutes, remainingSeconds)
    }
}

private extension PersonalRecordKind {
    var sortOrder: Int {
        switch self {
        case .highestJumpCount:
            0
        case .longestJumpStreak:
            1
        case .longestSession:
            2
        case .mostCalories:
            3
        case .bestJumpRate:
            4
        @unknown default:
            Int.max
        }
    }
}
