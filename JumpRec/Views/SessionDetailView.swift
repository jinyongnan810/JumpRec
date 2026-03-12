//
//  SessionDetailView.swift
//  JumpRec
//

import JumpRecShared
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    @Environment(MyDataStore.self) private var dataStore
    let session: JumpSession
    @State private var isGeneratingComment = false

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
        .task(id: session.id) {
            await generateCommentIfNeeded()
        }
    }

    private var peakRateText: String {
        guard let peak = session.peakRate else { return "–" }
        return "\(Int(peak))/min"
    }

    private var averageRateText: String {
        guard let average = session.averageRate else { return "–" }
        return "\(Int(average))/min"
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

    private func generateCommentIfNeeded() async {
        guard SessionAICommentGenerator.shouldGenerate(for: session) else { return }
        guard session.aiComment == nil else { return }
        guard SessionAICommentGenerator.isAvailable else { return }

        isGeneratingComment = true
        _ = await dataStore.generateAICommentIfNeeded(for: session)
        isGeneratingComment = false
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
        caloriesBurned: 198,
        smallBreaksCount: 3,
        longBreaksCount: 1
    )
    container.mainContext.insert(session)

    return NavigationStack {
        SessionDetailView(session: session)
    }
    .modelContainer(container)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
