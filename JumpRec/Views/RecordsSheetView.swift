//
//  RecordsSheetView.swift
//  JumpRec
//

import SwiftData
import SwiftUI

struct RecordsSheetView: View {
    @Query(sort: \PersonalRecord.kindRawValue) private var records: [PersonalRecord]
    @Environment(MyDataStore.self) private var dataStore
    @State private var isShowingClearRecordsConfirmation = false

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
            .sorted { $0.achievedAt > $1.achievedAt }
    }

    private var unseenRecordKinds: [PersonalRecordKind] {
        dataStore.unseenPersonalRecordKinds
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Records list
                    if displayRecords.isEmpty {
                        VStack(spacing: 8) {
                            Spacer()
                            Text("No records yet")
                                .font(AppFonts.bodyLabelStrong)
                                .foregroundStyle(AppColors.textSecondary)
                            Text("Complete sessions to set personal records!")
                                .font(AppFonts.bodySmall)
                                .foregroundStyle(AppColors.textMuted)
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(displayRecords) { record in
                                RecordCardView(
                                    record: record,
                                    isHighlighted: unseenRecordKinds.contains(record.kind)
                                ).padding(.horizontal, 12)
                            }
                        }
                    }

                    Spacer()
                }
            }
            .padding(.top, 16)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    if !unseenRecordKinds.isEmpty {
                        PersonalRecordBadgeView(style: .pill)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if !displayRecords.isEmpty {
                        Button(role: .destructive) {
                            // The destructive action is split from the tap target so the sheet can present
                            // a confirmation step before removing every cached personal record.
                            isShowingClearRecordsConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .accessibilityLabel(Text("Delete Records"))
                    }
                }
            }
            .alert(
                "Delete all records?",
                isPresented: $isShowingClearRecordsConfirmation
            ) {
                Button("Delete Records", role: .destructive) {
                    dataStore.clearAllPersonalRecords()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all personal records from this sheet. Your saved sessions stay in history.")
            }
            .onDisappear {
                // Dismissing the records sheet counts as acknowledging any newly achieved records.
                dataStore.clearUnseenPersonalRecordUpdates()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    let dataStore = MyDataStore.shared
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
            achievedAt: calendar.date(byAdding: .day, value: -4, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .longestJumpStreak,
            metricValue: 642,
            displayValue: "642 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .longestSession,
            metricValue: 900,
            displayValue: "15:00",
            achievedAt: calendar.date(byAdding: .day, value: -5, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .mostCalories,
            metricValue: 384,
            displayValue: "384 cal",
            achievedAt: calendar.date(byAdding: .day, value: -2, to: now)!
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
    container.mainContext.insert(
        PersonalRecord(
            kind: .steadyRhythm,
            metricValue: 0.92,
            displayValue: "92%",
            achievedAt: calendar.date(byAdding: .day, value: -6, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .bestAverageJumpRate,
            metricValue: 168,
            displayValue: "168/min",
            achievedAt: calendar.date(byAdding: .day, value: -7, to: now)!
        )
    )
    container.mainContext.insert(
        PersonalRecord(
            kind: .sneakyBurn,
            metricValue: 24.6,
            displayValue: "24.6 kcal/min",
            achievedAt: calendar.date(byAdding: .day, value: -8, to: now)!
        )
    )

    dataStore.markUnseenPersonalRecordUpdates([.highestJumpCount, .steadyRhythm, .sneakyBurn])

    return
        RecordsSheetView()
            .modelContainer(container)
            .environment(dataStore)
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
    let isHighlighted: Bool

    private static let cardBg = Color(hex: 0x0F172A)

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.kind.icon)
                .font(AppFonts.screenTitleRegular)
                .foregroundStyle(AppColors.accent)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(record.kind.title))
                    .font(AppFonts.bodyRegular)
                    .foregroundStyle(AppColors.textPrimary)

                HStack {
                    Text(displayValue)
                        .font(AppFonts.statValueMonospaced)
                        .foregroundStyle(AppColors.accent)

                    Spacer()

                    Text(Self.dateFormatter.string(from: record.achievedAt))
                        .font(AppFonts.supportingMonospaced)
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .padding(16)
        .background(Self.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(alignment: .topTrailing) {
            if isHighlighted {
                PersonalRecordBadgeView(style: .compact)
                    .offset(x: 6, y: -6)
            }
        }
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
            return Measurement(value: record.metricValue, unit: UnitEnergy.kilocalories)
                .formatted(
                    .measurement(
                        width: .abbreviated,
                        usage: .workout,
                        numberFormatStyle: .number.precision(.fractionLength(0))
                    )
                )
        case .bestJumpRate:
            return localizedRateText(Int(record.metricValue.rounded()))
        case .steadyRhythm:
            return localizedPercentText(record.metricValue)
        case .bestAverageJumpRate:
            return localizedRateText(Int(record.metricValue.rounded()))
        case .sneakyBurn:
            return localizedCaloriesPerMinuteText(record.metricValue)
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
