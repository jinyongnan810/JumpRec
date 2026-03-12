//
//  JumpingRateGraphView.swift
//  JumpRec
//

import Charts
import SwiftUI

struct JumpingRateGraphView: View {
    let samples: [SessionRateSample]

    private let gridLineColor = Color(hex: 0x0F172A)
    private let yAxisStepCount = 3
    private let xAxisStepCount = 4

    var body: some View {
        Group {
            if chartPoints.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.tabInactive.opacity(0.35), lineWidth: 1)
                    .overlay {
                        Text("No data")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                    }
            } else {
                Chart(chartPoints) { point in
                    AreaMark(
                        x: .value("Elapsed Time", point.elapsedSeconds),
                        y: .value("Rate", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                AppColors.accent.opacity(0.2),
                                AppColors.accent.opacity(0.0),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )

                    LineMark(
                        x: .value("Elapsed Time", point.elapsedSeconds),
                        y: .value("Rate", point.value)
                    )
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    .foregroundStyle(AppColors.accent)
                }
                .chartLegend(.hidden)
                .chartXScale(domain: chartXDomain)
                .chartYScale(domain: chartYDomain)
                .chartXAxis {
                    AxisMarks(values: xAxisMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0))
                        AxisValueLabel {
                            if let elapsedSeconds = value.as(Int.self),
                               let label = xAxisLabelMap[elapsedSeconds]
                            {
                                Text(label)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppColors.tabInactive)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: yAxisMarks.map(\.value)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(gridLineColor)
                        AxisTick(stroke: StrokeStyle(lineWidth: 0))
                        AxisValueLabel(anchor: .trailing) {
                            if let axisValue = value.as(Double.self),
                               let mark = yAxisMarks.first(where: { abs($0.value - axisValue) < 0.0001 })
                            {
                                Text(mark.label)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundStyle(AppColors.tabInactive)
                            }
                        }
                    }
                }
                .chartPlotStyle { plotArea in
                    plotArea
                        .background(Color.clear)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var chartPoints: [ChartPoint] {
        samples
            .sorted { $0.secondOffset < $1.secondOffset }
            .map { sample in
                ChartPoint(elapsedSeconds: sample.secondOffset, value: sample.rate)
            }
    }

    private var chartXDomain: ClosedRange<Int> {
        let upperBound = max(chartPoints.map(\.elapsedSeconds).max() ?? 0, 1)
        return 0 ... upperBound
    }

    private var chartYDomain: ClosedRange<Double> {
        let values = chartPoints.map(\.value)
        guard let minValue = values.min(), let maxValue = values.max() else {
            return 0 ... 1
        }

        if abs(maxValue - minValue) < 0.0001 {
            let upperBound = max(1, maxValue * 1.1)
            return 0 ... upperBound
        }

        return 0 ... maxValue
    }

    private var xAxisMarks: [Int] {
        let durationSeconds = chartXDomain.upperBound
        guard durationSeconds > 0 else { return [0] }

        return (0 ... xAxisStepCount).map { step in
            Int((Double(step) / Double(xAxisStepCount) * Double(durationSeconds)).rounded())
        }
    }

    private var xAxisLabelMap: [Int: String] {
        Dictionary(uniqueKeysWithValues: xAxisMarks.map { seconds in
            (seconds, formattedElapsedTime(seconds))
        })
    }

    private var yAxisMarks: [ChartAxisLabel] {
        let lowerBound = chartYDomain.lowerBound
        let upperBound = chartYDomain.upperBound
        let span = upperBound - lowerBound

        guard span > 0 else {
            return [
                ChartAxisLabel(
                    value: lowerBound,
                    label: formattedYAxisValue(lowerBound)
                ),
            ]
        }

        return (0 ... yAxisStepCount).map { step in
            let progress = Double(step) / Double(yAxisStepCount)
            let value = lowerBound + (span * progress)
            return ChartAxisLabel(value: value, label: formattedYAxisValue(value))
        }
    }

    private func formattedYAxisValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    private func formattedElapsedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

private struct ChartPoint: Identifiable {
    let elapsedSeconds: Int
    let value: Double

    var id: Int { elapsedSeconds }
}

private struct ChartAxisLabel {
    let value: Double
    let label: String
}

#Preview {
    JumpingRateGraphView(
        samples: {
            let session = JumpSession(
                startedAt: .now,
                endedAt: .now.addingTimeInterval(332),
                jumpCount: 847,
                peakRate: 180,
                averageRate: 153,
                caloriesBurned: 156
            )

            let values = [107, 115, 130, 135, 145, 160, 165, 180, 170, 150, 155, 165, 150, 130, 135, 145, 155, 165, 170, 150]
            let step = 332 / max(values.count - 1, 1)

            return values.enumerated().map { index, value in
                SessionRateSample(session: session, secondOffset: index * step, rate: Double(value))
            }
        }()
    )
    .frame(height: 170)
    .padding(16)
    .background(AppColors.cardSurface)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
