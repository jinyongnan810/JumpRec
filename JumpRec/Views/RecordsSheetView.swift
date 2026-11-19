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
    @State private var recordPendingDeletion: RecordItem?
    @State private var isShowingDeleteRecordConfirmation = false

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
                    !record.isDeleted,
                    let kindRawValue = record.kindRawValue,
                    let kind = PersonalRecordKind(rawValue: kindRawValue),
                    let metricValue = record.metricValue,
                    let achievedAt = record.achievedAt
                else {
                    return nil
                }

                return RecordItem(
                    id: record.persistentModelID,
                    record: record,
                    kind: kind,
                    metricValue: metricValue,
                    achievedAt: achievedAt
                )
            }
            .sorted {
                if $0.achievedAt != $1.achievedAt {
                    return $0.achievedAt > $1.achievedAt
                }
                if $0.kind.rawValue != $1.kind.rawValue {
                    return $0.kind.rawValue < $1.kind.rawValue
                }
                if $0.metricValue != $1.metricValue {
                    return $0.metricValue > $1.metricValue
                }
                return String(describing: $0.id) < String(describing: $1.id)
            }
    }

    private var unseenRecordKinds: [PersonalRecordKind] {
        dataStore.unseenPersonalRecordKinds
    }

    var body: some View {
        NavigationStack {
            Group {
                if displayRecords.isEmpty {
                    ScrollView {
                        VStack(spacing: 20) {
                            VStack(spacing: 8) {
                                Spacer()
                                Text("No records yet")
                                    .font(AppFonts.bodyLabelStrong)
                                    .foregroundStyle(AppColors.textSecondary)
                                Text("Complete workouts to set personal records!")
                                    .font(AppFonts.bodySmall)
                                    .foregroundStyle(AppColors.textMuted)
                                Spacer()
                            }
                            .frame(maxWidth: .infinity)

                            Spacer()
                        }
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                    .topSoftScrollEdgeEffect()
                } else {
                    List {
                        ForEach(displayRecords) { record in
                            RecordCardView(
                                record: record,
                                isHighlighted: unseenRecordKinds.contains(record.kind)
                            )
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 5, leading: 36, bottom: 5, trailing: 36))
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                // Omit role: .destructive so UIKit does not attempt row deletion before confirmation.
                                Button {
                                    promptDeleteRecord(record)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .contentMargins(.top, 11, for: .scrollContent)
                    .contentMargins(.bottom, 27, for: .scrollContent)
                    .topSoftScrollEdgeEffect()
                }
            }
            .navigationTitle("Personal Records")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if !displayRecords.isEmpty {
                        Button(role: .destructive) {
                            // Confirm before clearing cached personal records.
                            isShowingClearRecordsConfirmation = true
                        } label: {
                            Image(systemName: "trash")
                        }
                        .foregroundStyle(.red)
                        .tint(.red)
                        .accessibilityLabel(Text("Delete Records"))
                    }
                }
            }
            .modifier(
                DeleteSingleRecordAlertModifier(
                    record: $recordPendingDeletion,
                    isPresented: $isShowingDeleteRecordConfirmation,
                    onDelete: confirmDeleteRecord
                )
            )
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
            Text("This removes all personal records from this sheet. Your saved workouts stay in history.")
        }
        .onDisappear {
            // Dismissing the records sheet counts as acknowledging any newly achieved records.
            dataStore.clearUnseenPersonalRecordUpdates()
        }
    }

    private func promptDeleteRecord(_ item: RecordItem) {
        recordPendingDeletion = item
        if #unavailable(iOS 27.0) {
            isShowingDeleteRecordConfirmation = true
        }
    }

    private func confirmDeleteRecord(_ item: RecordItem) {
        dataStore.deletePersonalRecord(item.record)
        recordPendingDeletion = nil
        isShowingDeleteRecordConfirmation = false
    }
}

// MARK: - Preview

#Preview {
    let dataStore = try! MyDataStore.makePreviewStore(qualifiedWorkoutCount: 0)
    let context = dataStore.modelContext

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
        context.insert(session)
    }

    context.insert(
        PersonalRecord(
            kind: .highestJumpCount,
            metricValue: 2847,
            displayValue: "2,847 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -4, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .longestJumpStreak,
            metricValue: 642,
            displayValue: "642 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -1, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .longestSession,
            metricValue: 900,
            displayValue: "15:00",
            achievedAt: calendar.date(byAdding: .day, value: -5, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .mostCalories,
            metricValue: 384,
            displayValue: "384 cal",
            achievedAt: calendar.date(byAdding: .day, value: -2, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .bestJumpRate,
            metricValue: 186,
            displayValue: "186/min",
            achievedAt: calendar.date(byAdding: .day, value: -3, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .steadyRhythm,
            metricValue: 0.92,
            displayValue: "92%",
            achievedAt: calendar.date(byAdding: .day, value: -6, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .bestAverageJumpRate,
            metricValue: 168,
            displayValue: "168/min",
            achievedAt: calendar.date(byAdding: .day, value: -7, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .sneakyBurn,
            metricValue: 24.6,
            displayValue: "24.6 kcal/min",
            achievedAt: calendar.date(byAdding: .day, value: -8, to: now)!
        )
    )
    context.insert(
        PersonalRecord(
            kind: .mostDoubleUnders,
            metricValue: 48,
            displayValue: "48 jumps",
            achievedAt: calendar.date(byAdding: .day, value: -2, to: now)!
        )
    )

    dataStore.markUnseenPersonalRecordUpdates([.highestJumpCount, .steadyRhythm, .sneakyBurn])

    return
        RecordsSheetView()
            .modelContainer(dataStore.modelContainer)
            .environment(dataStore)
            .presentationBackground(AppColors.cardSurface)
            .preferredColorScheme(.dark)
}

// MARK: - Delete Single Record Alert

/// Presents a confirmation alert before deleting an individual personal record.
private struct DeleteSingleRecordAlertModifier: ViewModifier {
    @Binding var record: RecordItem?
    @Binding var isPresented: Bool
    let onDelete: (RecordItem) -> Void

    func body(content: Content) -> some View {
        if #available(iOS 27.0, *) {
            content.alert("Delete this record?", item: $record) { item in
                Button("Delete Record", role: .destructive) {
                    onDelete(item)
                }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                Text("This removes this personal record from this sheet. Your saved workouts stay in history.")
            }
        } else {
            content
                .alert(
                    "Delete this record?",
                    isPresented: $isPresented,
                    presenting: record
                ) { item in
                    Button("Delete Record", role: .destructive) {
                        onDelete(item)
                    }
                    Button("Cancel", role: .cancel) {
                        record = nil
                    }
                } message: { _ in
                    Text("This removes this personal record from this sheet. Your saved workouts stay in history.")
                }
                .onChange(of: isPresented) { _, presented in
                    if !presented {
                        record = nil
                    }
                }
        }
    }
}

// MARK: - Record Item Model

private struct RecordItem: Identifiable {
    let id: PersistentIdentifier
    let record: PersonalRecord
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
                Text(record.kind.title)
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
        // Position the badge above the compact record row.
        .dotIndicatorOverlay(isVisible: isHighlighted)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(isHighlighted ? Text("New personal record.") : Text(""))
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.setLocalizedDateFormatFromTemplate("yMMMd")
        return formatter
    }()

    /// Names the record type for VoiceOver using the same localized title shown visually.
    private var accessibilityLabel: Text {
        Text(record.kind.title)
    }

    /// Combines the record value and date so the compact row is understandable without relying on layout.
    private var accessibilityValue: Text {
        Text("\(displayValue), achieved \(Self.dateFormatter.string(from: record.achievedAt))")
    }

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
        case .mostDoubleUnders:
            return String(
                format: String(localized: "%@ jumps"),
                Int(record.metricValue.rounded()).formatted()
            )
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
