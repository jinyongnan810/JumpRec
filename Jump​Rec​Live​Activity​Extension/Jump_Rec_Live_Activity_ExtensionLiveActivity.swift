//
//  Jump_Rec_Live_Activity_ExtensionLiveActivity.swift
//  JumpRecLiveActivityExtension
//

import ActivityKit
import SwiftUI
import WidgetKit

private func localizedSourceLabel(for sourceLabel: String) -> String {
    switch sourceLabel {
    case "Watch":
        String(localized: "Watch")
    case "Headphone":
        String(localized: "Headphone")
    case "AirPods":
        String(localized: "AirPods")
    default:
        String(localized: "iPhone")
    }
}

struct JumpRecLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JumpRecLiveActivityAttributes.self) { context in
            JumpRecLiveActivityView(context: context)
                .activityBackgroundTint(AppColors.bgPrimary.opacity(0.92))
                .activitySystemActionForegroundColor(AppColors.textPrimary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    metricView(
                        title: String(localized: "Jumps"),
                        value: "\(context.state.jumpCount)"
                    )
                }

                DynamicIslandExpandedRegion(.trailing) {
                    metricView(
                        title: String(localized: "Rate"),
                        value: localizedRateText(context.state.averageRate)
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(context.attributes.goalSummary)
                            .font(AppFonts.liveActivityCaption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            metricView(
                                title: String(localized: "Calories"),
                                value: "\(context.state.caloriesBurned)"
                            )
                            metricView(
                                title: String(localized: "Source"),
                                value: localizedSourceLabel(for: context.state.sourceLabel)
                            )
                        }

                        timerView(context: context)
                    }
                }
            } compactLeading: {
                Text("\(context.state.jumpCount)")
                    .font(AppFonts.liveActivityHeadline)
                    .foregroundStyle(AppColors.textPrimary)
            } compactTrailing: {
                Image(systemName: iconName(for: context.state.sourceLabel))
                    .font(AppFonts.liveActivityHeadline)
                    .foregroundStyle(AppColors.accent)
            } minimal: {
                Image(systemName: iconName(for: context.state.sourceLabel))
                    .foregroundStyle(AppColors.accent)
            }
            .keylineTint(AppColors.accent)
        }
    }

    private func metricView(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(AppFonts.liveActivityCaption2)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.liveActivityHeadline)
                .foregroundStyle(AppColors.textPrimary)
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
        .font(AppFonts.liveActivityTimer)
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
                        .font(AppFonts.liveActivityHeadline)
                        .foregroundStyle(AppColors.textPrimary)
                    Text(context.attributes.goalSummary)
                        .font(AppFonts.liveActivityCaption)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Label(localizedSourceLabel(for: context.state.sourceLabel), systemImage: iconName)
                        .font(AppFonts.liveActivityCaptionSemibold)
                        .foregroundStyle(AppColors.accent)
                    durationView
                }
            }

            HStack(spacing: 12) {
                statCard(title: String(localized: "Jumps"), value: "\(context.state.jumpCount)")
                statCard(title: String(localized: "Calories"), value: "\(context.state.caloriesBurned)")
                statCard(title: String(localized: "Rate"), value: localizedRateText(context.state.averageRate))
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .foregroundStyle(AppColors.textPrimary)
    }

    @ViewBuilder
    private var durationView: some View {
        if let endedAt = context.state.endedAt {
            let interval = Int(endedAt.timeIntervalSince(context.attributes.startedAt))
            Text(String(format: "%02d:%02d", interval / 60, interval % 60))
                .font(AppFonts.liveActivityTimer)
                .foregroundStyle(AppColors.textPrimary)
        } else {
            Text(context.attributes.startedAt, style: .timer)
                .font(AppFonts.liveActivityTimer)
                .foregroundStyle(AppColors.textPrimary)
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
                .font(AppFonts.liveActivityCaption2)
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppFonts.liveActivityHeadline)
                .foregroundStyle(AppColors.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(AppColors.cardSurface.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
    }
}
