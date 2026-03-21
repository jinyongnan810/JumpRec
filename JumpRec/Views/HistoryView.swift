//
//  HistoryView.swift
//  JumpRec
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \PersonalRecord.kindRawValue) private var personalRecords: [PersonalRecord]

    @Environment(\.modelContext) private var modelContext

    @Namespace private var navigationTransitionNamespace
    private static let recordsTransitionID = "records"
    @State private var displayedMonth = Date()
    @State private var showRecords = false
    @State private var selectedSession: JumpSession?
    @State private var sessionsPendingDeletion: [JumpSession] = []
    @State private var showingDeleteConfirmation = false
    @State private var isDeletingAllSessions = false

    private var calendar: Calendar { Calendar.current }

    private var displayedMonthRange: DateInterval? {
        let comps = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: .month, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    var body: some View {
        NavigationStack {
            if let displayedMonthRange {
                MonthSessionsList(
                    displayedMonth: displayedMonth,
                    monthRange: displayedMonthRange,
                    navigationTransitionNamespace: navigationTransitionNamespace,
                    selectedSession: $selectedSession,
                    onPreviousMonth: {
                        displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                    },
                    onNextMonth: {
                        displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                    },
                    onDeleteSessions: promptDeleteSessions
                )
            } else {
                ContentUnavailableView("Unable to load this month.", systemImage: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.bgPrimary)
            }
        }
        .navigationDestination(item: $selectedSession) { session in
            SessionDetailView(session: session)
                .navigationTransition(.zoom(sourceID: session.id, in: navigationTransitionNamespace))
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showRecords = true
                } label: {
                    Label("Records", systemImage: "trophy.fill")
                }
                .matchedTransitionSource(id: Self.recordsTransitionID, in: navigationTransitionNamespace)
            }
            #if DEBUG
                ToolbarItem(placement: .topBarLeading) {
                    Button(role: .destructive) {
                        promptDeleteAllSessions()
                    } label: {
                        Label("Delete All", systemImage: "trash")
                    }
                }
            #endif
        }
        .sheet(isPresented: $showRecords) {
            RecordsSheetView()
                .navigationTransition(.zoom(sourceID: Self.recordsTransitionID, in: navigationTransitionNamespace))
                .presentationDetents([.large, .medium])
                .presentationDragIndicator(.visible)
                .presentationBackground(AppColors.cardSurface)
        }
        .deleteSessionAlert(
            isPresented: $showingDeleteConfirmation,
            sessionCount: sessionsPendingDeletion.count,
            onDelete: confirmDeleteSessions
        )
    }

    private func promptDeleteSessions(_ sessions: [JumpSession]) {
        isDeletingAllSessions = false
        sessionsPendingDeletion = sessions
        showingDeleteConfirmation = !sessionsPendingDeletion.isEmpty
    }

    private func confirmDeleteSessions() {
        let shouldDeletePersonalRecords = isDeletingAllSessions

        for session in sessionsPendingDeletion {
            modelContext.delete(session)
        }

        if shouldDeletePersonalRecords {
            for record in personalRecords {
                modelContext.delete(record)
            }
        }

        do {
            try modelContext.save()
            sessionsPendingDeletion = []
            isDeletingAllSessions = false
        } catch {
            print("Failed to delete sessions: \(error)")
        }
    }

    private func promptDeleteAllSessions() {
        let descriptor = FetchDescriptor<JumpSession>()

        guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else { return }
        isDeletingAllSessions = true
        sessionsPendingDeletion = sessions
        showingDeleteConfirmation = true
    }
}

private struct MonthSessionsList: View {
    @Query private var sessions: [JumpSession]

    let displayedMonth: Date
    let monthRange: DateInterval
    let navigationTransitionNamespace: Namespace.ID
    @Binding var selectedSession: JumpSession?
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onDeleteSessions: ([JumpSession]) -> Void

    private var calendar: Calendar { Calendar.current }

    init(
        displayedMonth: Date,
        monthRange: DateInterval,
        navigationTransitionNamespace: Namespace.ID,
        selectedSession: Binding<JumpSession?>,
        onPreviousMonth: @escaping () -> Void,
        onNextMonth: @escaping () -> Void,
        onDeleteSessions: @escaping ([JumpSession]) -> Void
    ) {
        self.displayedMonth = displayedMonth
        self.monthRange = monthRange
        self.navigationTransitionNamespace = navigationTransitionNamespace
        _selectedSession = selectedSession
        self.onPreviousMonth = onPreviousMonth
        self.onNextMonth = onNextMonth
        self.onDeleteSessions = onDeleteSessions

        let start = monthRange.start
        let end = monthRange.end
        let predicate = #Predicate<JumpSession> { session in
            session.startedAt >= start && session.startedAt < end
        }
        _sessions = Query(filter: predicate, sort: \JumpSession.startedAt, order: .reverse)
    }

    /// Set of day-of-month integers that have sessions
    private var sessionDays: Set<Int> {
        Set(sessions.map { calendar.component(.day, from: $0.startedAt) })
    }

    /// Total jump count per day-of-month
    private var jumpsByDay: [Int: Int] {
        var result: [Int: Int] = [:]
        for session in sessions {
            let day = calendar.component(.day, from: session.startedAt)
            result[day, default: 0] += session.jumpCount
        }
        return result
    }

    /// Total jumps for the displayed month
    private var totalJumps: Int {
        sessions.reduce(0) { $0 + $1.jumpCount }
    }

    /// Total time for the displayed month
    private var totalDuration: TimeInterval {
        sessions.reduce(0) { total, session in
            total + session.endedAt.timeIntervalSince(session.startedAt)
        }
    }

    var body: some View {
        List {
            Section {
                HistoryCalendarView(
                    displayedMonth: displayedMonth,
                    sessionDays: sessionDays,
                    jumpsByDay: jumpsByDay,
                    onPreviousMonth: onPreviousMonth,
                    onNextMonth: onNextMonth
                )
                .listRowSeparator(.hidden)
            }

            Section {
                HStack(spacing: 12) {
                    StatCardView(label: "SESSIONS", value: "\(sessions.count)", valueColor: AppColors.accent)
                    StatCardView(label: "JUMPS", value: formatCount(totalJumps))
                    StatCardView(label: "TIME", value: formatDuration(totalDuration))
                }
                .listRowSeparator(.hidden)
            }

            Section {
                if sessions.isEmpty {
                    Text("No sessions in this month.")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                } else {
                    ForEach(sessions, id: \.id) { session in
                        Button {
                            selectedSession = session
                        } label: {
                            SessionRowView(session: session)
                                .matchedTransitionSource(id: session.id, in: navigationTransitionNamespace)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        .listRowSeparator(.hidden)
                    }
                    .onDelete(perform: deleteSessions)
                }
            } header: {
                Text("SESSIONS THIS MONTH")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
                    .textCase(nil)
                    .padding(.horizontal, 24)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func deleteSessions(at offsets: IndexSet) {
        onDeleteSessions(offsets.map { sessions[$0] })
    }

    private func formatCount(_ value: Int) -> String {
        if value >= 10000 {
            let k = Double(value) / 1000.0
            return String(format: "%.1fK", k)
        }
        return value.formatted()
    }

    // ⭐️ Format localize string with unit
    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let allowedUnits: Set<Duration.UnitsFormatStyle.Unit> = hours > 0 ? [.hours, .minutes] : [.minutes]

        return Duration.seconds(duration).formatted(
            .units(allowed: allowedUnits, width: .abbreviated)
        )
    }
}

// MARK: - Session Row

private struct SessionRowView: View {
    let session: JumpSession

    private var dateText: String {
        session.startedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var durationText: String {
        let duration = session.endedAt.timeIntervalSince(session.startedAt)
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]

        return formatter.string(from: duration) ?? "0:00"
    }

    private var caloriesText: String {
        // ⭐️Measurements format with unit
        Measurement(value: session.caloriesBurned, unit: UnitEnergy.kilocalories)
            .formatted(.measurement(width: .abbreviated, usage: .workout, numberFormatStyle: .number.precision(.fractionLength(0))))
    }

    private var showsCalories: Bool {
        session.caloriesBurned > 0
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(dateText)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        jumpsChip
                        durationChip
                        if showsCalories {
                            caloriesChip
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            jumpsChip
                            durationChip
                        }

                        if showsCalories {
                            caloriesChip
                        }
                    }
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

    private var jumpsChip: some View {
        metricChip(
            systemImage: "figure.jumprope",
            value: session.jumpCount.formatted(),
            valueColor: AppColors.accent,
            accessibilityLabel: String(localized: "Jumps")
        )
    }

    private var durationChip: some View {
        metricChip(
            systemImage: "timer",
            value: durationText,
            accessibilityLabel: String(localized: "Duration")
        )
    }

    private var caloriesChip: some View {
        metricChip(
            systemImage: "flame.fill",
            value: caloriesText,
            accessibilityLabel: String(localized: "Calories")
        )
    }

    private func metricChip(
        systemImage: String,
        value: String,
        valueColor: Color = AppColors.textSecondary,
        accessibilityLabel: String
    ) -> some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
//        .background(AppColors.bgPrimary.opacity(0.45))
//        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value)
    }
}

// MARK: - Preview

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: JumpSession.self,
        SessionRateSample.self,
        configurations: config
    )

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
