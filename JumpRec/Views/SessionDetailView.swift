//
//  SessionDetailView.swift
//  JumpRec
//

import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(MyDataStore.self) private var dataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let session: JumpSession
    @State private var isGeneratingComment = false
    @State private var showingDeleteConfirmation = false

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy, h:mm a"
        return formatter.string(from: session.startedAt)
    }

    private var durationText: String {
        let seconds = Int(session.endedAt.timeIntervalSince(session.startedAt))
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private var rateSamples: [SessionRateSample] {
        (session.rateSamples ?? []).sorted { $0.secondOffset < $1.secondOffset }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date Row
                HStack {
                    Text(dateText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()
                }

                if SessionAICommentGenerator.shouldGenerate(for: session) {
                    if let aiComment = session.aiComment {
                        AICommentCardView(comment: aiComment, isLoading: false)
                    } else if isGeneratingComment {
                        AICommentCardView(comment: nil, isLoading: true)
                    }
                }

                SessionMetricsSummaryView(
                    duration: durationText,
                    jumps: session.jumpCount.formatted(),
                    calories: "\(Int(session.caloriesBurned))",
                    averageRate: averageRateText,
                    peakRate: peakRateText,
                    longestJumpStrikes: longestJumpStrikesText,
                    shortBreaks: "\(session.smallBreaksCount)",
                    longBreaks: "\(session.longBreaksCount)",
                    averageHeartRate: averageHeartRateText,
                    peakHeartRate: peakHeartRateText,
                    rateSamples: rateSamples
                )
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showingDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .deleteSessionAlert(isPresented: $showingDeleteConfirmation, onDelete: deleteSession)
        .task(id: session.id) {
            await generateCommentIfNeeded()
        }
    }

    private var peakRateText: String {
        guard let peak = session.peakRate else { return "–" }
        return localizedRateText(Int(peak))
    }

    private var averageRateText: String {
        guard let average = session.averageRate else { return "–" }
        return localizedRateText(Int(average))
    }

    private func generateCommentIfNeeded() async {
        guard SessionAICommentGenerator.shouldGenerate(for: session) else { return }
        guard session.aiComment == nil else { return }
        guard SessionAICommentGenerator.isAvailable else { return }

        isGeneratingComment = true
        _ = await dataStore.generateAICommentIfNeeded(for: session)
        isGeneratingComment = false
    }

    private func deleteSession() {
        modelContext.delete(session)

        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Failed to delete session: \(error)")
        }
    }

    private var longestJumpStrikesText: String {
        "–"
    }

    private var averageHeartRateText: String {
        "–"
    }

    private var peakHeartRateText: String {
        "–"
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

    let start = Calendar.current.date(byAdding: .minute, value: -7, to: Date())!
    let end = Date()
    let session = JumpSession(
        startedAt: start,
        endedAt: end,
        jumpCount: 1024,
        peakRate: 168,
        averageRate: 142,
        caloriesBurned: 198,
        smallBreaksCount: 3,
        longBreaksCount: 1,
        longestStreak: 186,
        averageHeartRate: 144,
        peakHeartRate: 172,
        aiComment: "Strong mid-session pace with solid consistency. You held a high cadence and kept breaks under control."
    )
    container.mainContext.insert(session)

    let sampleData: [(Int, Double)] = [
        (0, 96), (30, 118), (60, 136), (90, 154),
        (120, 168), (150, 162), (180, 148), (210, 140),
        (240, 146), (270, 152), (300, 144), (330, 132),
        (360, 124), (390, 116), (420, 108),
    ]

    for (secondOffset, rate) in sampleData {
        let sample = SessionRateSample(session: session, secondOffset: secondOffset, rate: rate)
        container.mainContext.insert(sample)
        if session.rateSamples == nil {
            session.rateSamples = []
        }
        session.rateSamples?.append(sample)
    }

    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
    .environment(MyDataStore.shared)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
