//
//  HistoryView.swift
//  JumpRec
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    /// Checks for history with a one-row fetch.
    private static var sessionExistenceDescriptor: FetchDescriptor<JumpSession> {
        var descriptor = FetchDescriptor<JumpSession>(
            sortBy: [SortDescriptor(\.startedAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    @Query(sort: \PersonalRecord.kindRawValue) private var personalRecords: [PersonalRecord]
    @Query(Self.sessionExistenceDescriptor) private var sessionExistenceProbe: [JumpSession]

    @Environment(MyDataStore.self) private var dataStore
    @Environment(\.modelContext) private var modelContext

    @Namespace private var navigationTransitionNamespace
    private static let recordsTransitionID = "records"
    private enum HistoryScope: String, CaseIterable {
        case month = "Month"
        case year = "Year"

        var localizedTitle: LocalizedStringKey {
            switch self {
            case .month:
                "Month"
            case .year:
                "Year"
            }
        }
    }

    @State private var selectedScope: HistoryScope = .month
    @State private var displayedMonth = Date()
    @State private var displayedYear = Date()
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

    private var displayedYearRange: DateInterval? {
        let year = calendar.component(.year, from: displayedYear)
        let comps = DateComponents(year: year, month: 1, day: 1)
        guard let start = calendar.date(from: comps),
              let end = calendar.date(byAdding: .year, value: 1, to: start) else { return nil }
        return DateInterval(start: start, end: end)
    }

    /// Combines the local query and reactive count to detect history after CloudKit imports.
    private var hasSessions: Bool {
        !sessionExistenceProbe.isEmpty || dataStore.hasLocalSessions
    }

    var body: some View {
        NavigationStack {
            Group {
                if !hasSessions {
                    emptyLibraryState
                } else {
                    VStack(spacing: 0) {
                        Picker("Scope", selection: $selectedScope) {
                            ForEach(HistoryScope.allCases, id: \.self) { scope in
                                Text(scope.localizedTitle).tag(scope)
                            }
                        }
                        .pickerStyle(.segmented)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 8)
                        .background(AppColors.bgPrimary)

                        if selectedScope == .month {
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
                                    onDeleteSessions: promptDeleteSessions,
                                    onRefresh: {
                                        await dataStore.manualSyncCheck()
                                    }
                                )
                            } else {
                                ContentUnavailableView(String(localized: "Unable to load this month."), systemImage: "calendar")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(AppColors.bgPrimary)
                            }
                        } else {
                            if let displayedYearRange {
                                YearSessionsList(
                                    displayedYear: displayedYear,
                                    yearRange: displayedYearRange,
                                    navigationTransitionNamespace: navigationTransitionNamespace,
                                    selectedSession: $selectedSession,
                                    onPreviousYear: {
                                        displayedYear = calendar.date(byAdding: .year, value: -1, to: displayedYear) ?? displayedYear
                                    },
                                    onNextYear: {
                                        displayedYear = calendar.date(byAdding: .year, value: 1, to: displayedYear) ?? displayedYear
                                    },
                                    onDeleteSessions: promptDeleteSessions,
                                    onRefresh: {
                                        await dataStore.manualSyncCheck()
                                    }
                                )
                            } else {
                                ContentUnavailableView(String(localized: "Unable to load this year."), systemImage: "calendar")
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .background(AppColors.bgPrimary)
                            }
                        }
                    }
                }
            }
            .onChange(of: selectedScope) { _, newScope in
                if newScope == .year {
                    syncDisplayedYearWithMonth()
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
                    .dotIndicatorOverlay(
                        isVisible: !dataStore.unseenPersonalRecordKinds.isEmpty,
                        size: 200,
                        offset: CGSize(width: 95, height: -95)
                    )
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
                    .presentationContentInteraction(.scrolls)
            }
            .deleteSessionAlert(
                isPresented: $showingDeleteConfirmation,
                sessionCount: sessionsPendingDeletion.count,
                onDelete: confirmDeleteSessions
            )
        }
        .onAppear {
            dataStore.refreshLocalSessionCount()
        }
        .onChange(of: sessionExistenceProbe.isEmpty) { _, _ in
            dataStore.refreshLocalSessionCount()
        }
        .onChange(of: dataStore.hasLocalSessions) { _, _ in
            dataStore.refreshLocalSessionCount()
        }
    }

    /// Title header for the current active sync state.
    private var syncStatusTitle: String {
        switch dataStore.cloudSyncPhase {
        case .importing:
            String(localized: "Downloading from iCloud...")
        case .exporting:
            String(localized: "Uploading to iCloud...")
        case .connecting:
            String(localized: "Connecting to iCloud...")
        case .failed:
            String(localized: "Sync Failed")
        case .idle:
            String(localized: "Syncing from iCloud...")
        }
    }

    /// Empty workout history with pull-to-refresh and CloudKit sync status.
    private var emptyLibraryState: some View {
        ScrollView {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "figure.jumprope")
                    .font(.system(size: 52))
                    .foregroundStyle(AppColors.accent.opacity(0.85))
                    .padding(.bottom, 4)

                Text("No workouts yet")
                    .font(AppFonts.sectionTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text("Workouts recorded on your Apple Watch or iPhone will appear here.")
                    .font(AppFonts.bodyRegular)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)

                if dataStore.isCloudSyncActive {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(AppColors.accent)
                        Text(syncStatusTitle)
                            .font(AppFonts.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(AppColors.cardSurface)
                    .clipShape(Capsule())
                    .padding(.top, 8)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, minHeight: 440)
        }
        .scrollBounceBehavior(.always)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.bgPrimary)
        .refreshable {
            await dataStore.manualSyncCheck()
        }
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
            dataStore.refreshLocalSessionCount()
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

    /// Synchronizes `displayedYear` to match the year currently shown in `displayedMonth`.
    private func syncDisplayedYearWithMonth() {
        let yearComp = calendar.component(.year, from: displayedMonth)
        let comps = DateComponents(year: yearComp, month: 1, day: 1)
        if let syncedDate = calendar.date(from: comps) {
            displayedYear = syncedDate
        }
    }
}

private struct MonthSessionsList: View {
    @Query private var sessions: [JumpSession]

    /// Controls the calendar's one-time entrance without replaying it during month navigation.
    @State private var hasCalendarAppeared = false

    /// Replays the summary and row entrance sequence when the displayed month changes.
    @State private var hasAppeared = false

    let displayedMonth: Date
    let monthRange: DateInterval
    let navigationTransitionNamespace: Namespace.ID
    @Binding var selectedSession: JumpSession?
    let onPreviousMonth: () -> Void
    let onNextMonth: () -> Void
    let onDeleteSessions: ([JumpSession]) -> Void
    let onRefresh: () async -> Void

    private var calendar: Calendar { Calendar.current }

    init(
        displayedMonth: Date,
        monthRange: DateInterval,
        navigationTransitionNamespace: Namespace.ID,
        selectedSession: Binding<JumpSession?>,
        onPreviousMonth: @escaping () -> Void,
        onNextMonth: @escaping () -> Void,
        onDeleteSessions: @escaping ([JumpSession]) -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        self.displayedMonth = displayedMonth
        self.monthRange = monthRange
        self.navigationTransitionNamespace = navigationTransitionNamespace
        _selectedSession = selectedSession
        self.onPreviousMonth = onPreviousMonth
        self.onNextMonth = onNextMonth
        self.onDeleteSessions = onDeleteSessions
        self.onRefresh = onRefresh

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
                .staggeredAppearance(isVisible: hasCalendarAppeared, index: 0)
            }

            Section {
                HStack(spacing: 12) {
                    StatCardView(label: "WORKOUTS", value: "\(sessions.count)", valueColor: AppColors.accent)
                    StatCardView(label: "JUMPS", value: formatCount(totalJumps))
                    StatCardView(label: "TIME", value: formatDuration(totalDuration))
                }
                // Sizing the HStack to its tallest child's ideal height guarantees matching card heights across all languages.
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)
                .staggeredAppearance(isVisible: hasAppeared, index: 1)
            }

            Section {
                if sessions.isEmpty {
                    Text("No workouts in this month.")
                        .font(AppFonts.bodyRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .staggeredAppearance(isVisible: hasAppeared, index: 2)
                } else {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            selectedSession = session
                        } label: {
                            SessionRowView(session: session)
                                .matchedTransitionSource(id: session.id, in: navigationTransitionNamespace)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        .listRowSeparator(.hidden)
                        .staggeredAppearance(isVisible: hasAppeared, index: index + 2)
                    }
                    .onDelete(perform: deleteSessions)
                }
            } header: {
                Text("WORKOUTS THIS MONTH")
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
                    .textCase(nil)
                    .padding(.horizontal, 24)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .topSoftScrollEdgeEffect()
        .refreshable {
            await onRefresh()
        }
        .task {
            // Keep the calendar's entrance independent of month navigation.
            await Task.yield()
            hasCalendarAppeared = true
        }
        .task(id: displayedMonth) {
            // Reset without animation, then render the new query results before revealing them.
            hasAppeared = false
            await Task.yield()
            hasAppeared = true
        }
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
            .units(allowed: allowedUnits, width: .narrow)
        )
    }
}

// MARK: - Year Sessions List

private struct YearSessionsList: View {
    @Query private var sessions: [JumpSession]

    @State private var hasHeaderAppeared = false
    @State private var hasAppeared = false

    let displayedYear: Date
    let yearRange: DateInterval
    let navigationTransitionNamespace: Namespace.ID
    @Binding var selectedSession: JumpSession?
    let onPreviousYear: () -> Void
    let onNextYear: () -> Void
    let onDeleteSessions: ([JumpSession]) -> Void
    let onRefresh: () async -> Void

    private var calendar: Calendar { Calendar.current }

    init(
        displayedYear: Date,
        yearRange: DateInterval,
        navigationTransitionNamespace: Namespace.ID,
        selectedSession: Binding<JumpSession?>,
        onPreviousYear: @escaping () -> Void,
        onNextYear: @escaping () -> Void,
        onDeleteSessions: @escaping ([JumpSession]) -> Void,
        onRefresh: @escaping () async -> Void
    ) {
        self.displayedYear = displayedYear
        self.yearRange = yearRange
        self.navigationTransitionNamespace = navigationTransitionNamespace
        _selectedSession = selectedSession
        self.onPreviousYear = onPreviousYear
        self.onNextYear = onNextYear
        self.onDeleteSessions = onDeleteSessions
        self.onRefresh = onRefresh

        let start = yearRange.start
        let end = yearRange.end
        let predicate = #Predicate<JumpSession> { session in
            session.startedAt >= start && session.startedAt < end
        }
        _sessions = Query(filter: predicate, sort: \JumpSession.startedAt, order: .reverse)
    }

    /// The calendar year integer (e.g. 2026).
    private var yearNumber: Int {
        calendar.component(.year, from: displayedYear)
    }

    /// Total jumps for the displayed year
    private var totalJumps: Int {
        sessions.reduce(0) { $0 + $1.jumpCount }
    }

    /// Total time for the displayed year
    private var totalDuration: TimeInterval {
        sessions.reduce(0) { total, session in
            total + session.endedAt.timeIntervalSince(session.startedAt)
        }
    }

    var body: some View {
        List {
            Section {
                HistoryYearSummaryCard(
                    year: yearNumber,
                    totalJumps: totalJumps,
                    workoutCount: sessions.count,
                    onPreviousYear: onPreviousYear,
                    onNextYear: onNextYear
                )
                .listRowSeparator(.hidden)
                .staggeredAppearance(isVisible: hasHeaderAppeared, index: 0)
            }

            Section {
                HStack(spacing: 12) {
                    StatCardView(label: "WORKOUTS", value: "\(sessions.count)", valueColor: AppColors.accent)
                    StatCardView(label: "JUMPS", value: formatCount(totalJumps))
                    StatCardView(label: "TIME", value: formatDuration(totalDuration))
                }
                // Sizing the HStack to its tallest child's ideal height guarantees matching card heights across all languages.
                .fixedSize(horizontal: false, vertical: true)
                .listRowSeparator(.hidden)
                .staggeredAppearance(isVisible: hasAppeared, index: 1)
            }

            Section {
                if sessions.isEmpty {
                    Text(String(format: String(localized: "No workouts in %d."), yearNumber))
                        .font(AppFonts.bodyRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                        .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                        .staggeredAppearance(isVisible: hasAppeared, index: 2)
                } else {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { index, session in
                        Button {
                            selectedSession = session
                        } label: {
                            SessionRowView(session: session)
                                .matchedTransitionSource(id: session.id, in: navigationTransitionNamespace)
                        }
                        .buttonStyle(.plain)
                        .listRowInsets(EdgeInsets(top: 4, leading: 24, bottom: 4, trailing: 24))
                        .listRowSeparator(.hidden)
                        .staggeredAppearance(isVisible: hasAppeared, index: index + 2)
                    }
                    .onDelete(perform: deleteSessions)
                }
            } header: {
                Text(String(format: String(localized: "WORKOUTS IN %d"), yearNumber))
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)
                    .textCase(nil)
                    .padding(.horizontal, 24)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .topSoftScrollEdgeEffect()
        .refreshable {
            await onRefresh()
        }
        .task {
            await Task.yield()
            hasHeaderAppeared = true
        }
        .task(id: displayedYear) {
            hasAppeared = false
            await Task.yield()
            hasAppeared = true
        }
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

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = Int(duration)
        let hours = totalSeconds / 3600
        let allowedUnits: Set<Duration.UnitsFormatStyle.Unit> = hours > 0 ? [.hours, .minutes] : [.minutes]

        return Duration.seconds(duration).formatted(
            .units(allowed: allowedUnits, width: .narrow)
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
                    .font(AppFonts.bodyLabel)
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
                .font(AppFonts.sectionIcon)
                .foregroundStyle(AppColors.tabInactive)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens workout details."))
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
                .font(AppFonts.badgeLabel)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.smallValueMonospaced)
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(value)
    }
}

// MARK: - Preview

#Preview {
    let dataStore = MyDataStore.shared
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(
        for: JumpSession.self,
        PersonalRecord.self,
        SessionRateSeries.self,
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

    dataStore.markUnseenPersonalRecordUpdates([.highestJumpCount, .steadyRhythm, .sneakyBurn])

    return HistoryView()
        .modelContainer(container)
        .environment(dataStore)
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
