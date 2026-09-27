//
//  YearSummaryDesignPreviews.swift
//  JumpRec
//

#if DEBUG
    import SwiftUI

    /// Design preview for Option 2: Segmented [Month | Year] control with inline details.
    ///
    /// Key Design Principles:
    /// 1. **Zero Route Collisions**: Preserves `HistoryView`'s real navigation bar (`History` title and the `Records 🏆` trophy button).
    /// 2. **Symmetric Layout**:
    ///    - **Month Tab**: `< Month >` calendar card ➔ 3 stat cards ➔ inline monthly sessions list.
    ///    - **Year Tab**: `< Year >` summary card ➔ 3 stat cards ➔ inline annual sessions list.
    /// 3. **Inline Simplicity**: No push transitions or extra screens. Tapping `<` / `>` (or selecting a year pill)
    ///    updates the annual stat cards and session list right inline on the same screen.

    // MARK: - Canvas Helper

    /// JumpRec standard dark theme canvas wrapper for previews.
    private struct YearSummaryPreviewCanvas<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            ZStack {
                AppColors.bgPrimary.ignoresSafeArea()
                content
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Mock Models

    /// Represents a recorded jump workout for previewing session rows.
    private struct MockSession: Identifiable {
        let id = UUID()
        let date: Date
        let jumpCount: Int
        let durationSeconds: TimeInterval
        let calories: Double

        var durationText: String {
            let minutes = Int(durationSeconds) / 60
            let seconds = Int(durationSeconds) % 60
            return String(format: "%02d:%02d", minutes, seconds)
        }

        var formattedDate: String {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            return formatter.string(from: date)
        }
    }

    /// Summary information for one year.
    private struct YearSummaryItem: Identifiable {
        var id: Int { year }
        let year: Int
        let totalJumps: Int
        let workoutCount: Int
        let totalDurationSeconds: TimeInterval

        var formattedJumps: String {
            if totalJumps >= 1000 {
                return String(format: "%.1fK", Double(totalJumps) / 1000.0)
            }
            return "\(totalJumps)"
        }

        var formattedDuration: String {
            let hours = Int(totalDurationSeconds) / 3600
            let minutes = (Int(totalDurationSeconds) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    // MARK: - Mock Data

    private enum YearSummaryMockData {
        static let years: [YearSummaryItem] = [
            YearSummaryItem(year: 2026, totalJumps: 142_800, workoutCount: 186, totalDurationSeconds: 139_200),
            YearSummaryItem(year: 2025, totalJumps: 98420, workoutCount: 142, totalDurationSeconds: 96000),
            YearSummaryItem(year: 2024, totalJumps: 42100, workoutCount: 64, totalDurationSeconds: 43200),
        ]

        /// Sample workouts for the active month.
        static var currentMonthSessions: [MockSession] {
            let calendar = Calendar.current
            let now = Date()
            return [
                MockSession(date: calendar.date(byAdding: .day, value: -1, to: now)!, jumpCount: 1024, durationSeconds: 424, calories: 198),
                MockSession(date: calendar.date(byAdding: .day, value: -3, to: now)!, jumpCount: 847, durationSeconds: 312, calories: 156),
                MockSession(date: calendar.date(byAdding: .day, value: -6, to: now)!, jumpCount: 1200, durationSeconds: 480, calories: 210),
                MockSession(date: calendar.date(byAdding: .day, value: -9, to: now)!, jumpCount: 632, durationSeconds: 240, calories: 112),
                MockSession(date: calendar.date(byAdding: .day, value: -12, to: now)!, jumpCount: 950, durationSeconds: 360, calories: 175),
            ]
        }

        /// Sample workouts for a selected year.
        static func yearSessions(for year: Int) -> [MockSession] {
            let calendar = Calendar.current
            var components = DateComponents(year: year, month: 10, day: 15, hour: 8, minute: 30)
            let baseDate = calendar.date(from: components) ?? Date()

            return [
                MockSession(date: baseDate, jumpCount: 1850, durationSeconds: 620, calories: 245),
                MockSession(date: calendar.date(byAdding: .day, value: -14, to: baseDate)!, jumpCount: 1420, durationSeconds: 510, calories: 190),
                MockSession(date: calendar.date(byAdding: .day, value: -35, to: baseDate)!, jumpCount: 2100, durationSeconds: 780, calories: 290),
                MockSession(date: calendar.date(byAdding: .day, value: -60, to: baseDate)!, jumpCount: 1150, durationSeconds: 430, calories: 165),
                MockSession(date: calendar.date(byAdding: .day, value: -90, to: baseDate)!, jumpCount: 980, durationSeconds: 380, calories: 140),
                MockSession(date: calendar.date(byAdding: .day, value: -120, to: baseDate)!, jumpCount: 1600, durationSeconds: 590, calories: 220),
            ]
        }
    }

    // MARK: - Reusable Session Row

    /// Renders a workout row matching the production `SessionRowView` in `HistoryView`.
    private struct MockSessionRowView: View {
        let session: MockSession

        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text(session.formattedDate)
                        .font(AppFonts.bodyLabelStrong)
                        .foregroundStyle(AppColors.textPrimary)

                    HStack(spacing: 10) {
                        metricChip(
                            systemImage: "figure.jumprope",
                            value: session.jumpCount.formatted(),
                            valueColor: AppColors.accent
                        )
                        metricChip(
                            systemImage: "timer",
                            value: session.durationText
                        )
                        metricChip(
                            systemImage: "flame.fill",
                            value: "\(Int(session.calories)) kcal"
                        )
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
        }

        private func metricChip(
            systemImage: String,
            value: String,
            valueColor: Color = AppColors.textSecondary
        ) -> some View {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(AppFonts.iconLabel)
                    .foregroundStyle(valueColor)

                Text(value)
                    .font(AppFonts.metricDetailMonospaced)
                    .foregroundStyle(valueColor)
            }
        }
    }

    // MARK: - Year Card Component (Header in Year Tab)

    /// A clean card displayed at the top of the Year tab, matching `HistoryCalendarView`'s layout and weight.
    /// Allows cycling years via `<` and `>` buttons or horizontal swipe gestures.
    private struct YearSelectorHeaderCard: View {
        let selectedYear: Int
        let summary: YearSummaryItem
        let canGoPrevious: Bool
        let canGoNext: Bool
        let onPreviousYear: () -> Void
        let onNextYear: () -> Void

        var body: some View {
            VStack(spacing: 14) {
                // Header with year number and chevron buttons
                HStack {
                    Button(action: onPreviousYear) {
                        Image(systemName: "chevron.left")
                            .font(AppFonts.sectionIcon)
                            .foregroundStyle(canGoPrevious ? AppColors.textSecondary : AppColors.tabInactive.opacity(0.4))
                            .frame(width: 32, height: 32)
                    }
                    .appGlassButton()
                    .buttonBorderShape(.circle)
                    .disabled(!canGoPrevious)
                    .accessibilityLabel(Text("Previous year"))

                    Spacer()

                    Text(verbatim: String(selectedYear))
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()

                    Button(action: onNextYear) {
                        Image(systemName: "chevron.right")
                            .font(AppFonts.sectionIcon)
                            .foregroundStyle(canGoNext ? AppColors.textSecondary : AppColors.tabInactive.opacity(0.4))
                            .frame(width: 32, height: 32)
                    }
                    .appGlassButton()
                    .buttonBorderShape(.circle)
                    .disabled(!canGoNext)
                    .accessibilityLabel(Text("Next year"))
                }

                // Simple metric presentation: total jumps for the year
                VStack(spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(summary.formattedJumps)
                            .font(AppFonts.metricValueXLMonospaced)
                            .foregroundStyle(AppColors.accent)

                        Text("JUMPS")
                            .font(AppFonts.eyebrowLabel)
                            .tracking(2)
                            .foregroundStyle(AppColors.textMuted)
                    }

                    Text(verbatim: "\(summary.workoutCount) workouts in \(selectedYear)")
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
                        if value.translation.width < -50, canGoNext {
                            onNextYear()
                        } else if value.translation.width > 50, canGoPrevious {
                            onPreviousYear()
                        }
                    }
            )
        }
    }

    // MARK: - Option 2: Inline Year Tab View (Primary Concept)

    /// Segmented `[Month | Year]` view where the Year tab displays details inline,
    /// exactly matching the visual structure of the Month tab.
    private struct Option2InlineYearSummaryView: View {
        enum Scope: String, CaseIterable {
            case month = "Month"
            case year = "Year"
        }

        @State private var selectedScope: Scope = .year
        @State private var selectedYearIndex: Int = 0
        @State private var displayedMonth = Date()
        @State private var showSimulatedRecords = false

        private var availableYears: [YearSummaryItem] {
            YearSummaryMockData.years
        }

        private var currentYearSummary: YearSummaryItem {
            availableYears[selectedYearIndex]
        }

        private let sampleSessionDays: Set<Int> = [2, 5, 8, 12, 15, 20, 24]
        private let sampleJumpsByDay: [Int: Int] = [
            2: 650, 5: 1200, 8: 847, 12: 1024, 15: 632, 20: 950, 24: 1850,
        ]

        var body: some View {
            NavigationStack {
                VStack(spacing: 0) {
                    // Segmented control right below the navigation bar
                    Picker("Scope", selection: $selectedScope) {
                        ForEach(Scope.allCases, id: \.self) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(AppColors.bgPrimary)

                    ScrollView {
                        VStack(spacing: 16) {
                            if selectedScope == .month {
                                monthTabInlineContent
                            } else {
                                yearTabInlineContent
                            }
                        }
                        .padding(16)
                    }
                    .background(AppColors.bgPrimary)
                }
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    // Real production Records button preserved in topBarTrailing
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSimulatedRecords = true
                        } label: {
                            Image(systemName: "trophy.fill")
                                .foregroundStyle(AppColors.accent)
                        }
                        .accessibilityLabel(Text("Records"))
                    }
                }
                .sheet(isPresented: $showSimulatedRecords) {
                    simulatedRecordsSheet
                }
            }
        }

        // MARK: - Month Tab Content

        private var monthTabInlineContent: some View {
            VStack(spacing: 16) {
                // 1. Month Calendar Card
                HistoryCalendarView(
                    displayedMonth: displayedMonth,
                    sessionDays: sampleSessionDays,
                    jumpsByDay: sampleJumpsByDay,
                    onPreviousMonth: {
                        if let prev = Calendar.current.date(byAdding: .month, value: -1, to: displayedMonth) {
                            displayedMonth = prev
                        }
                    },
                    onNextMonth: {
                        if let next = Calendar.current.date(byAdding: .month, value: 1, to: displayedMonth) {
                            displayedMonth = next
                        }
                    }
                )

                // 2. Three Monthly Stat Cards
                HStack(spacing: 12) {
                    StatCardView(
                        label: "WORKOUTS",
                        value: "\(YearSummaryMockData.currentMonthSessions.count)",
                        valueColor: AppColors.accent
                    )
                    StatCardView(
                        label: "JUMPS",
                        value: "5.6K"
                    )
                    StatCardView(
                        label: "TIME",
                        value: "34m"
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                // 3. Workouts List Header
                HStack {
                    Text("WORKOUTS THIS MONTH")
                        .font(AppFonts.eyebrowLabel)
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
                .padding(.top, 4)

                // 4. Session Rows
                VStack(spacing: 10) {
                    ForEach(YearSummaryMockData.currentMonthSessions) { session in
                        MockSessionRowView(session: session)
                    }
                }
            }
        }

        // MARK: - Year Tab Content (Symmetric to Month Tab!)

        private var yearTabInlineContent: some View {
            VStack(spacing: 16) {
                // 1. Year Summary Header Card (Matches HistoryCalendarView's weight and style)
                YearSelectorHeaderCard(
                    selectedYear: currentYearSummary.year,
                    summary: currentYearSummary,
                    canGoPrevious: selectedYearIndex < availableYears.count - 1,
                    canGoNext: selectedYearIndex > 0,
                    onPreviousYear: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedYearIndex < availableYears.count - 1 {
                                selectedYearIndex += 1
                            }
                        }
                    },
                    onNextYear: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            if selectedYearIndex > 0 {
                                selectedYearIndex -= 1
                            }
                        }
                    }
                )

                // 2. Three Annual Stat Cards (Exact same layout and styling as Month tab)
                HStack(spacing: 12) {
                    StatCardView(
                        label: "WORKOUTS",
                        value: "\(currentYearSummary.workoutCount)",
                        valueColor: AppColors.accent
                    )
                    StatCardView(
                        label: "JUMPS",
                        value: currentYearSummary.formattedJumps
                    )
                    StatCardView(
                        label: "TIME",
                        value: currentYearSummary.formattedDuration
                    )
                }
                .fixedSize(horizontal: false, vertical: true)

                // 3. Workouts List Header
                HStack {
                    Text(verbatim: "WORKOUTS IN \(currentYearSummary.year)")
                        .font(AppFonts.eyebrowLabel)
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
                .padding(.top, 4)

                // 4. Session Rows for the selected year
                VStack(spacing: 10) {
                    ForEach(YearSummaryMockData.yearSessions(for: currentYearSummary.year)) { session in
                        MockSessionRowView(session: session)
                    }
                }
            }
        }

        private var simulatedRecordsSheet: some View {
            ZStack {
                AppColors.cardSurface.ignoresSafeArea()
                VStack(spacing: 16) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.accent)
                    Text("Personal Records")
                        .font(AppFonts.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("This is the existing Records sheet opened by the trophy button in the header.")
                        .font(AppFonts.bodyRegular)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Close") {
                        showSimulatedRecords = false
                    }
                    .appGlassButton(tint: AppColors.accent)
                }
            }
            .presentationDetents([.medium])
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Alternative: Year Tab with Quick Year Pills

    /// A slight variation where the Year card also includes quick-select pills for all available years.
    private struct YearTabWithPillsAlternativeView: View {
        @State private var selectedYear: Int = 2026

        private var availableYears: [YearSummaryItem] {
            YearSummaryMockData.years
        }

        private var selectedYearSummary: YearSummaryItem {
            availableYears.first(where: { $0.year == selectedYear }) ?? availableYears[0]
        }

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 16) {
                        // Quick Year Selector Pills
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(availableYears) { item in
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.2)) {
                                            selectedYear = item.year
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("\(item.year)")
                                                .font(AppFonts.cardTitle)
                                            Text(item.formattedJumps)
                                                .font(AppFonts.supportingMonospaced)
                                                .foregroundStyle(selectedYear == item.year ? AppColors.accent : AppColors.textSecondary)
                                        }
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(selectedYear == item.year ? AppColors.cardSurface : AppColors.cardSurface.opacity(0.4))
                                        .foregroundStyle(selectedYear == item.year ? AppColors.textPrimary : AppColors.textSecondary)
                                        .clipShape(Capsule())
                                        .overlay(
                                            Capsule()
                                                .stroke(selectedYear == item.year ? AppColors.accent : Color.clear, lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }

                        // Three Stat Cards
                        HStack(spacing: 12) {
                            StatCardView(
                                label: "WORKOUTS",
                                value: "\(selectedYearSummary.workoutCount)",
                                valueColor: AppColors.accent
                            )
                            StatCardView(
                                label: "JUMPS",
                                value: selectedYearSummary.formattedJumps
                            )
                            StatCardView(
                                label: "TIME",
                                value: selectedYearSummary.formattedDuration
                            )
                        }
                        .fixedSize(horizontal: false, vertical: true)

                        // Workouts List
                        HStack {
                            Text(verbatim: "WORKOUTS IN \(selectedYear)")
                                .font(AppFonts.eyebrowLabel)
                                .tracking(2)
                                .foregroundStyle(AppColors.textMuted)
                            Spacer()
                        }
                        .padding(.top, 4)

                        VStack(spacing: 10) {
                            ForEach(YearSummaryMockData.yearSessions(for: selectedYear)) { session in
                                MockSessionRowView(session: session)
                            }
                        }
                    }
                    .padding(16)
                }
                .background(AppColors.bgPrimary)
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Image(systemName: "trophy.fill")
                            .foregroundStyle(AppColors.accent)
                    }
                }
            }
        }
    }

    // MARK: - Previews

    #Preview("Option 2: [Month | Year] with Inline Details (Recommended)") {
        YearSummaryPreviewCanvas {
            Option2InlineYearSummaryView()
        }
    }

    #Preview("Alternative: Year Tab with Quick Year Pills") {
        YearSummaryPreviewCanvas {
            YearTabWithPillsAlternativeView()
        }
    }

#endif
