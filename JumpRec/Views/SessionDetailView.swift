//
//  SessionDetailView.swift
//  JumpRec
//

import JumpRecShared
import SwiftUI

struct SessionDetailView: View {
    let session: JumpSession
    @Environment(\.dismiss) private var dismiss

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
                // Nav Row
                HStack(spacing: 12) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18))
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(width: 36, height: 36)
                            .background(AppColors.cardSurface)
                            .clipShape(Circle())
                    }

                    Text("Session Details")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)

                    Spacer()
                }

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

                // Stats Grid
                VStack(spacing: 8) {
                    // Row 1: Duration, Jumps
                    HStack(spacing: 10) {
                        DetailStatCard(label: "DURATION", value: durationText)
                        DetailStatCard(label: "JUMPS", value: session.jumpCount.formatted(), valueColor: AppColors.accent)
                    }

                    // Row 2: Calories, Rate
                    HStack(spacing: 10) {
                        DetailStatCard(label: "CALORIES", value: "\(Int(session.caloriesBurned))")
                        DetailStatCard(label: "RATE", value: rateText)
                    }

                    // Row 3: Breaks, Heart Rate
                    HStack(spacing: 10) {
                        DetailStatCard(label: "BREAKS", value: "\(session.smallBreaksCount)/\(session.longBreaksCount)", valueColor: AppColors.warning)
                        DetailStatCard(label: "HEART RATE", value: "–/–", valueColor: AppColors.heartRate)
                    }
                }

                // Graph Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("JUMPING RATE")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)

                    JumpingRateGraphView(
                        dataPoints: graphDataPoints,
                        yLabels: ["200", "150", "100"],
                        xLabels: xLabels
                    )
                    .frame(height: 160)
                }
                .padding(16)
                .background(AppColors.cardSurface)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Session Breakdown
                VStack(alignment: .leading, spacing: 8) {
                    Text("SESSION BREAKDOWN")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(2)
                        .foregroundStyle(AppColors.textMuted)

                    // Goal Reached
                    BreakdownRow(label: "Goal Reached") {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppColors.accent)
                            Text(goalText)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .foregroundStyle(AppColors.accent)
                        }
                    }

                    // Peak Rate
                    BreakdownRow(label: "Peak Rate") {
                        Text(peakRateText)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    // Device
                    BreakdownRow(label: "Device") {
                        Text("iPhone")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .navigationBarHidden(true)
    }

    private var rateText: String {
        guard let peak = session.peakRate else { return "–" }
        // Estimate average as ~80% of peak for display
        let avg = Int(peak * 0.8)
        return "\(avg)/\(Int(peak))"
    }

    private var peakRateText: String {
        guard let peak = session.peakRate else { return "–" }
        return "\(Int(peak))/min"
    }

    private var goalText: String {
        "\(session.jumpCount.formatted()) jumps"
    }
}

// MARK: - Detail Stat Card

private struct DetailStatCard: View {
    let label: String
    let value: String
    var valueColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Breakdown Row

private struct BreakdownRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - CGFloat Clamped Helper

private extension CGFloat {
    func clamped(to range: ClosedRange<CGFloat>) -> CGFloat {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
