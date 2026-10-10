//
//  JumpingRateGraphView.swift
//  JumpRec
//

import Charts
import SwiftUI

/// Plots jump-rate samples over time for completed sessions.
struct JumpingRateGraphView: View {
    /// The rate samples used to render the chart.
    let samples: [RateSamplePoint]

    /// Prepared only when samples change; axis closures reuse this snapshot instead
    /// of remapping the full series for every tick and unrelated parent update.
    @State private var prepared = PreparedRateChart(samples: [])
    private let gridLineColor = Color(hex: 0x0F172A)

    // MARK: - View

    /// Renders the chart or an empty placeholder when no samples are available.
    var body: some View {
        Group {
            if prepared.chartPoints.isEmpty {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.tabInactive.opacity(0.35), lineWidth: 1)
                    .overlay {
                        Text("No data")
                            .font(AppFonts.secondaryActionLabel)
                            .foregroundStyle(AppColors.textSecondary)
                    }
            } else {
                Chart(prepared.chartPoints) { point in
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
                .chartXScale(domain: prepared.chartXDomain)
                .chartYScale(domain: prepared.chartYDomain)
                .chartXAxis {
                    AxisMarks(values: prepared.xAxisMarks) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 0))
                        AxisTick(stroke: StrokeStyle(lineWidth: 0))
                        AxisValueLabel {
                            if let elapsedSeconds = value.as(Int.self),
                               let label = prepared.xAxisLabelMap[elapsedSeconds]
                            {
                                Text(label)
                                    .font(AppFonts.graphAxisMonospaced)
                                    .foregroundStyle(AppColors.tabInactive)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading, values: prepared.yAxisMarks.map(\.value)) { value in
                        AxisGridLine(stroke: StrokeStyle(lineWidth: 1))
                            .foregroundStyle(gridLineColor)
                        AxisTick(stroke: StrokeStyle(lineWidth: 0))
                        AxisValueLabel(anchor: .trailing) {
                            if let axisValue = value.as(Double.self),
                               let mark = prepared.yAxisMarks.first(where: { abs($0.value - axisValue) < 0.0001 })
                            {
                                Text(mark.label)
                                    .font(AppFonts.graphAxisMonospaced)
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
        .onChange(of: samples, initial: true) { _, samples in
            prepared = PreparedRateChart(samples: samples)
        }
    }
}

/// Immutable plotted values and domains, prepared at the sample-change boundary.
private struct PreparedRateChart {
    let chartPoints: [ChartPoint]
    let chartXDomain: ClosedRange<Int>
    let chartYDomain: ClosedRange<Double>
    private let xAxisStepCount = 4
    private let yAxisStepCount = 3

    init(samples: [RateSamplePoint]) {
        chartPoints = samples.map { ChartPoint(elapsedSeconds: $0.secondOffset, value: Double($0.rate)) }
        chartXDomain = 0 ... max(samples.map(\.secondOffset).max() ?? 0, 1)
        let values = samples.map { Double($0.rate) }
        let minimum = values.min() ?? 0
        let maximum = values.max() ?? 0
        chartYDomain = 0 ... (abs(maximum - minimum) < 0.0001 ? max(1, maximum * 1.1) : maximum)
    }

    /// Returns the x-axis positions used for labels.
    var xAxisMarks: [Int] {
        let durationSeconds = chartXDomain.upperBound
        guard durationSeconds > 0 else { return [0] }

        // Short sessions can collapse multiple rounded steps onto the same second
        // (for example `[0, 1, 1, 2, 2]`). Deduplicating while preserving order keeps
        // the axis stable and avoids `Dictionary(uniqueKeysWithValues:)` trapping later
        // when labels are built from these marks.
        let rawMarks = (0 ... xAxisStepCount).map { step in
            Int((Double(step) / Double(xAxisStepCount) * Double(durationSeconds)).rounded())
        }

        var uniqueMarks: [Int] = []
        uniqueMarks.reserveCapacity(rawMarks.count)

        for mark in rawMarks where uniqueMarks.last != mark {
            uniqueMarks.append(mark)
        }

        if uniqueMarks.last != durationSeconds {
            uniqueMarks.append(durationSeconds)
        }

        return uniqueMarks
    }

    /// Maps x-axis positions to their formatted labels.
    var xAxisLabelMap: [Int: String] {
        Dictionary(uniqueKeysWithValues: xAxisMarks.map { seconds in
            (seconds, formattedElapsedTime(seconds))
        })
    }

    /// Returns the labeled y-axis marks used by the chart.
    var yAxisMarks: [ChartAxisLabel] {
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

    /// Formats y-axis values without fractional digits.
    private func formattedYAxisValue(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    /// Formats elapsed seconds as `m:ss`.
    private func formattedElapsedTime(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Represents one plotted point in the jump-rate chart.
private struct ChartPoint: Identifiable {
    /// The elapsed second associated with the point.
    let elapsedSeconds: Int
    /// The jump-rate value at that second.
    let value: Double

    /// Uses elapsed seconds as a stable identifier.
    var id: Int { elapsedSeconds }
}

/// Represents a labeled y-axis tick for the chart.
private struct ChartAxisLabel {
    /// The numeric axis value.
    let value: Double
    /// The formatted label shown for the axis value.
    let label: String
}

#Preview {
    JumpingRateGraphView(
        samples: {
            let values = [107, 115, 130, 135, 145, 160, 165, 180, 170, 150, 155, 165, 150, 130, 135, 145, 155, 165, 170, 150]
            let step = 332 / max(values.count - 1, 1)

            return values.enumerated().map { index, value in
                RateSamplePoint(secondOffset: index * step, rate: Float(value))
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
