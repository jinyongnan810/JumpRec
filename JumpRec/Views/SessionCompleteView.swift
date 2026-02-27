//
//  SessionCompleteView.swift
//  JumpRec
//

import SwiftUI

struct SessionCompleteView: View {
    var onDone: () -> Void

    // Placeholder session results
    private let duration = "05:32"
    private let jumps = 847
    private let calories = 156
    private let rateAvg = 153
    private let ratePeak = 179
    private let smallBreaks = 3
    private let longBreaks = 1
    private let heartRateAvg = 82
    private let heartRatePeak = 104

    // Placeholder graph data points (normalized 0–1 for y-axis range 100–200)
    private let graphPoints: [CGFloat] = [
        0.07, 0.15, 0.30, 0.35, 0.45, 0.60, 0.65, 0.80, 0.70, 0.50,
        0.55, 0.65, 0.50, 0.30, 0.35, 0.45, 0.55, 0.65, 0.70, 0.50,
    ]

    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(AppColors.accent)
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(AppColors.bgPrimary)
                }

                Text("Session Complete!")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text("Great workout! Here are your results.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
            }

            // Stats Grid
            VStack(spacing: 12) {
                // Row 1: Duration, Jumps
                HStack(spacing: 12) {
                    SummaryStatCard(label: "DURATION", value: duration)
                    SummaryStatCard(label: "JUMPS", value: "\(jumps)", valueColor: AppColors.accent)
                }

                // Row 2: Calories, Rate
                HStack(spacing: 12) {
                    SummaryStatCard(label: "CALORIES", value: "\(calories)")
                    SummaryStatCard(label: "RATE", value: "\(rateAvg)/\(ratePeak)")
                }

                // Row 3: Breaks, Heart Rate
                HStack(spacing: 12) {
                    SummaryStatCard(label: "BREAKS", value: "\(smallBreaks)/\(longBreaks)", valueColor: AppColors.warning)
                    SummaryStatCard(label: "HEART RATE", value: "\(heartRateAvg)/\(heartRatePeak)", valueColor: AppColors.heartRate)
                }
            }

            // Graph Section
            VStack(alignment: .leading, spacing: 12) {
                Text("JUMPING RATE")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                JumpingRateGraphView(
                    dataPoints: graphPoints,
                    yLabels: ["200", "150", "100"],
                    xLabels: ["0:00", "1:23", "2:46", "4:09", "5:32"]
                )
                .frame(height: 170)
            }
            .padding(16)
            .background(AppColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Spacer()

            // Done Button
            Button(action: onDone) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 18))
                    Text("Done")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(AppColors.bgPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(AppColors.accent)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Summary Stat Card (slightly larger than ActiveSession stat cards)

private struct SummaryStatCard: View {
    let label: String
    let value: String
    var valueColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Jumping Rate Graph

private struct JumpingRateGraphView: View {
    let dataPoints: [CGFloat]
    let yLabels: [String]
    let xLabels: [String]

    private let yAxisWidth: CGFloat = 35
    private let gridLineColor = Color(hex: 0x0F172A)

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .top, spacing: 0) {
                // Y-axis labels
                VStack {
                    ForEach(yLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.tabInactive)
                        if label != yLabels.last {
                            Spacer()
                        }
                    }
                }
                .frame(width: yAxisWidth)

                // Chart area
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height

                    ZStack(alignment: .topLeading) {
                        // Grid lines
                        ForEach(0 ..< 4) { i in
                            let y = h * CGFloat(i) / 3.0
                            Path { path in
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: w, y: y))
                            }
                            .stroke(gridLineColor, lineWidth: 1)
                        }

                        // Gradient fill
                        linePath(in: CGSize(width: w, height: h), closed: true)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColors.accent.opacity(0.2),
                                        AppColors.accent.opacity(0.0),
                                    ],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )

                        // Line stroke
                        linePath(in: CGSize(width: w, height: h), closed: false)
                            .stroke(AppColors.accent, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                }
            }

            // X-axis labels
            HStack {
                Spacer().frame(width: yAxisWidth)
                HStack {
                    ForEach(xLabels, id: \.self) { label in
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(AppColors.tabInactive)
                        if label != xLabels.last {
                            Spacer()
                        }
                    }
                }
            }
        }
    }

    private func linePath(in size: CGSize, closed: Bool) -> Path {
        guard dataPoints.count > 1 else { return Path() }

        let stepX = size.width / CGFloat(dataPoints.count - 1)

        return Path { path in
            for (index, point) in dataPoints.enumerated() {
                let x = stepX * CGFloat(index)
                let y = size.height * (1.0 - point)

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.addLine(to: CGPoint(x: x, y: y))
                }
            }

            if closed {
                path.addLine(to: CGPoint(x: size.width, y: size.height))
                path.addLine(to: CGPoint(x: 0, y: size.height))
                path.closeSubpath()
            }
        }
    }
}
