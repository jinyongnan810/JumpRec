//
//  Jump_Rec_Live_Activity_ExtensionLiveActivity.swift
//  JumpRecLiveActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

struct JumpRecLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JumpRecLiveActivityAttributes.self) { context in
            JumpRecLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.18))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metricView(
                        title: "Jumps",
                        value: "\(context.state.jumpCount)"
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    metricView(
                        title: "Rate",
                        value: "\(context.state.averageRate)/m"
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.attributes.goalSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            metricView(
                                title: "Calories",
                                value: "\(context.state.caloriesBurned)"
                            )
                            metricView(
                                title: "Source",
                                value: context.state.sourceLabel
                            )
                        }

                        timerView(context: context)
                    }
                }
            } compactLeading: {
                Text("\(context.state.jumpCount)")
                    .font(.headline)
            } compactTrailing: {
                Image(systemName: iconName(for: context.state.sourceLabel))
                    .font(.headline)
            } minimal: {
                Image(systemName: iconName(for: context.state.sourceLabel))
            }
        }
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    private func timerView(context: ActivityViewContext<JumpRecLiveActivityAttributes>) -> some View {
        Group {
            if let endedAt = context.state.endedAt {
                let interval = Int(endedAt.timeIntervalSince(context.attributes.startedAt))
                Text(String(format: "%02d:%02d", interval / 60, interval % 60))
            } else {
                Text(context.attributes.startedAt, style: .timer)
            }
        }
        .font(.title3.monospacedDigit())
    }

    private func iconName(for sourceLabel: String) -> String {
        switch sourceLabel {
        case "Watch":
            "applewatch"
        case "AirPods":
            "airpodspro"
        default:
            "iphone"
        }
    }
}

private struct JumpRecLiveActivityView: View {
    let context: ActivityViewContext<JumpRecLiveActivityAttributes>

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("JumpRec")
                        .font(.headline)
                    Text(context.attributes.goalSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label(context.state.sourceLabel, systemImage: iconName)
                        .font(.caption.weight(.semibold))
                    durationView
                }
            }

            HStack(spacing: 12) {
                statCard(title: "Jumps", value: "\(context.state.jumpCount)")
                statCard(title: "Calories", value: "\(context.state.caloriesBurned)")
                statCard(title: "Rate", value: "\(context.state.averageRate)/m")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var durationView: some View {
        if let endedAt = context.state.endedAt {
            let interval = Int(endedAt.timeIntervalSince(context.attributes.startedAt))
            Text(String(format: "%02d:%02d", interval / 60, interval % 60))
                .font(.title3.monospacedDigit())
        } else {
            Text(context.attributes.startedAt, style: .timer)
                .font(.title3.monospacedDigit())
        }
    }

    private var iconName: String {
        switch context.state.sourceLabel {
        case "Watch":
            "applewatch"
        case "AirPods":
            "airpodspro"
        default:
            "iphone"
        }
    }

    private func statCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }
}
