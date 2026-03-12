//
//  HistoryView.swift
//  JumpRec
//

import JumpRecShared
import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \JumpSession.startedAt, order: .reverse) var sessions: [JumpSession]

    @Environment(\.modelContext) private var modelContext

    @State private var displayedMonth = Date()
    @State private var showRecords = false
    @State private var selectedSession: JumpSession?
    @State private var sessionsPendingDeletion: [JumpSession] = []
    @State private var showingDeleteConfirmation = false

    private var calendar: Calendar { Calendar.current }

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

    /// Total time for the displayed month
    private var totalDuration: TimeInterval {
        sessionsInMonth.reduce(0) { total, session in
            total + session.endedAt.timeIntervalSince(session.startedAt)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HistoryCalendarView(
                        displayedMonth: displayedMonth,
                        sessionDays: sessionDays,
                        jumpsByDay: jumpsByDay,
                        onPreviousMonth: {
                            displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
                        },
                        onNextMonth: {
                            displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
                        }
                    ).listRowSeparator(.hidden)
                }

                Section {
                    HStack(spacing: 12) {
                        StatCardView(label: "SESSIONS", value: "\(sessionsInMonth.count)", valueColor: AppColors.accent)
                        StatCardView(label: "JUMPS", value: formatCount(totalJumps))
                        StatCardView(label: "TIME", value: formatDuration(totalDuration))
                    }
                    .listRowSeparator(.hidden)
                }

                Section {
                    if sessionsInMonth.isEmpty {
                        Text("No sessions in this month.")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 24)
                            .listRowInsets(EdgeInsets(top: 0, leading: 24, bottom: 0, trailing: 24))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    } else {
                        ForEach(sessionsInMonth, id: \.id) { session in
                            Button {
                                selectedSession = session
                            } label: {
                                SessionRowView(session: session)
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
            .navigationDestination(item: $selectedSession) { session in
                SessionDetailView(session: session)
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
                }
            }
        }
        .sheet(isPresented: $showRecords) {
            RecordsSheetView()
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
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }

        return String(format: "%dm", minutes)
    }

    private func deleteSessions(at offsets: IndexSet) {
        sessionsPendingDeletion = offsets.map { sessionsInMonth[$0] }
        showingDeleteConfirmation = !sessionsPendingDeletion.isEmpty
    }

    private func confirmDeleteSessions() {
        for session in sessionsPendingDeletion {
            modelContext.delete(session)
        }

        do {
            try modelContext.save()
            sessionsPendingDeletion = []
        } catch {
            print("Failed to delete sessions: \(error)")
        }
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
