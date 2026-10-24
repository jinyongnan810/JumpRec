import SwiftUI

/// Shows the headline metrics beside the rate chart when the content area is wide enough.
struct SessionMetricsOverviewView: View {
    let duration: String
    let jumps: String
    let calories: String
    let averageRate: String
    let rateSamples: [RateSamplePoint]
    let achievedRecordKinds: [PersonalRecordKind]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var availableWidth: CGFloat = 0

    var body: some View {
        let isHorizontal = availableWidth >= 600 && !dynamicTypeSize.isAccessibilitySize
        let layout = isHorizontal ? AnyLayout(HStackLayout(alignment: .top, spacing: 20)) : AnyLayout(VStackLayout(spacing: 20))

        layout {
            SessionHeadlineMetricsView(
                duration: duration,
                jumps: jumps,
                calories: calories,
                averageRate: averageRate,
                achievedRecordKinds: achievedRecordKinds
            )
            SessionRateChartView(samples: rateSamples)
        }
        .onGeometryChange(for: CGFloat.self) { geometry in
            geometry.size.width
        } action: { width in
            availableWidth = width
        }
    }
}

private struct SessionHeadlineMetricsView: View {
    let duration: String
    let jumps: String
    let calories: String
    let averageRate: String
    let achievedRecordKinds: [PersonalRecordKind]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: columns), spacing: 8) {
            SessionMetricCard(label: "DURATION", value: duration, showsBadge: achievedRecordKinds.contains(.longestSession))
            SessionMetricCard(label: "JUMPS", value: jumps, showsBadge: achievedRecordKinds.contains(.highestJumpCount))
            SessionMetricCard(label: "CALORIES", value: calories, showsBadge: achievedRecordKinds.contains(.mostCalories))
            SessionMetricCard(label: "AVG RATE", value: averageRate, showsBadge: achievedRecordKinds.contains(.bestAverageJumpRate))
        }
    }
}

private struct SessionRateChartView: View {
    let samples: [RateSamplePoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("JUMPING RATE")
                .font(AppFonts.badgeLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)
            JumpingRateGraphView(samples: samples)
                .frame(height: 160)
        }
        .padding(16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview("Wide Summary", traits: .fixedLayout(width: 800, height: 300)) {
    SessionMetricsOverviewView(
        duration: "08:12", jumps: "1,024", calories: "120", averageRate: "125/m",
        rateSamples: [], achievedRecordKinds: []
    )
    .padding(24)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
