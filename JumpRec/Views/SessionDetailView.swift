//
//  SessionDetailView.swift
//  JumpRec
//

import JumpRecShared
import SwiftData
import SwiftUI

struct SessionDetailView: View {
    let session: JumpSession

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

    private var durationSeconds: Int {
        Int(session.endedAt.timeIntervalSince(session.startedAt))
    }

    /// Generate x-axis time labels evenly spaced across the session duration
    private var xLabels: [String] {
        let total = durationSeconds
        guard total > 0 else { return ["0:00"] }
        return (0 ..< 5).map { i in
            let sec = total * i / 4
            let m = sec / 60
            let s = sec % 60
            return String(format: "%d:%02d", m, s)
        }
    }

    /// Convert rate points to normalized graph data (0–1 for y-axis range 100–200)
    private var graphDataPoints: [CGFloat] {
        guard let details = session.details else {
            return sampleGraphPoints
        }
        let points = details.ratePoints
        guard points.count > 1 else {
            return sampleGraphPoints
        }
        return points.map { point in
            CGFloat((point.rate - 100.0) / 100.0).clamped(to: 0 ... 1)
        }
    }

    // Fallback sample graph data when no rate points are available
    private let sampleGraphPoints: [CGFloat] = [
        0.07, 0.15, 0.30, 0.35, 0.45, 0.60, 0.65, 0.80, 0.70, 0.50,
        0.55, 0.65, 0.50, 0.30, 0.35, 0.45, 0.55, 0.65, 0.70, 0.50,
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Date Row
                HStack {
                    Text(dateText)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)

                    Spacer()

                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .font(.system(size: 12))
                        Text("iPhone")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(AppColors.accent)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(AppColors.cardSurface)
                    .clipShape(Capsule())
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
                    graphPoints: graphDataPoints,
                    xLabels: xLabels
                )
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .navigationTitle("Session Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var peakRateText: String {
        guard let peak = session.peakRate else { return "–" }
        return "\(Int(peak))/min"
    }

    private var averageRateText: String {
        guard let peak = session.peakRate else { return "–" }
        let average = Int(peak * 0.8)
        return "\(average)/min"
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
    let container = try! ModelContainer(for: JumpSession.self, configurations: config)

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

// MARK: - CGFloat Clamped Helper

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
