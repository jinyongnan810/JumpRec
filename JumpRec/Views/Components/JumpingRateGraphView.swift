//
//  JumpingRateGraphView.swift
//  JumpRec
//

import SwiftUI

struct JumpingRateGraphView: View {
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

#Preview {
    JumpingRateGraphView(
        dataPoints: [
            0.07, 0.15, 0.30, 0.35, 0.45, 0.60, 0.65, 0.80, 0.70, 0.50,
            0.55, 0.65, 0.50, 0.30, 0.35, 0.45, 0.55, 0.65, 0.70, 0.50,
        ],
        yLabels: ["200", "150", "100"],
        xLabels: ["0:00", "1:23", "2:46", "4:09", "5:32"]
    )
    .frame(height: 170)
    .padding(16)
    .background(AppColors.cardSurface)
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
