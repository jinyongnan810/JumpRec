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
        f.dateFormat = "MMM d, yyyy"
        return f
    }()

    private var displayRecords: [RecordItem] {
        records
            .compactMap { record in
                guard
                    let kindRawValue = record.kindRawValue,
                    let kind = PersonalRecordKind(rawValue: kindRawValue),
                    let value = record.displayValue,
                    let achievedAt = record.achievedAt
                else {
                    return nil
                }

                return RecordItem(
                    kind: kind,
                    value: value,
                    date: Self.dateFormatter.string(from: achievedAt)
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
    let value: String
    let date: String
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
                Text(record.kind.title)
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

private extension PersonalRecordKind {
    var sortOrder: Int {
        switch self {
        case .highestJumpCount:
            0
        case .longestSession:
            1
        case .mostCalories:
            2
        case .bestJumpRate:
            3
        @unknown default:
            Int.max
        }
    }
}
