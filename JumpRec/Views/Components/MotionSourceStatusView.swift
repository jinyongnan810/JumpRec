//
//  MotionSourceStatusView.swift
//  JumpRec
//

import SwiftUI

/// Presents the automatically resolved motion source without implying that users can select it.
struct MotionSourceStatusView: View {
    /// Defines whether the status describes the route before starting or the source of an active session.
    enum Presentation {
        case preSession
        case activeSession
    }

    /// The source that the app expects to use or is currently receiving motion data from.
    let source: DeviceSource?
    /// Stores the real connected headphone name when the system exposes one.
    let connectedHeadphoneName: String?
    /// Controls the wording and visual density for the current session phase.
    let presentation: Presentation

    // MARK: - View

    /// Renders one informational card rather than a row of controls that could be mistaken for a picker.
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(sectionTitle)
                .font(AppFonts.badgeLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            HStack(spacing: 14) {
                Image(systemName: source?.iconName ?? "sensor.tag.radiowaves.forward")
                    .font(AppFonts.sectionIcon)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 4) {
                    Text(statusTitle)
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text(statusDetail)
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, presentation == .activeSession ? 12 : 16)
            .background(AppColors.cardSurface)
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.accent.opacity(0.25), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sectionTitle)
        .accessibilityValue("\(statusTitle). \(statusDetail)")
    }

    // MARK: - Display Content

    /// Uses distinct labels so the home screen describes an upcoming route while the session screen reports live state.
    private var sectionTitle: String {
        switch presentation {
        case .preSession:
            String(localized: "SESSION DEVICE")
        case .activeSession:
            String(localized: "TRACKING SOURCE")
        }
    }

    /// Clearly states what the app will do instead of presenting the source name as a selectable option.
    private var statusTitle: String {
        switch (presentation, source) {
        case (.preSession, .watch):
            String(localized: "Session will start on Apple Watch")
        case (.preSession, .iPhone):
            String(localized: "Session will use iPhone")
        case (.preSession, .airpods):
            String(
                format: String(localized: "Session will use %@ when available"),
                displayName
            )
        case (.preSession, nil):
            String(localized: "No motion source available")
        case (.activeSession, .watch):
            String(localized: "Tracking on Apple Watch")
        case (.activeSession, .iPhone):
            String(localized: "Tracking with iPhone")
        case (.activeSession, .airpods):
            String(
                format: String(localized: "Tracking with %@"),
                displayName
            )
        case (.activeSession, nil):
            String(localized: "Starting motion tracking")
        }
    }

    /// Explains the automatic routing rules, including the important boundary between Watch and iPhone sessions.
    private var statusDetail: String {
        switch (presentation, source) {
        case (.preSession, .watch):
            String(localized: "If Apple Watch cannot start, iPhone will be used.")
        case (.preSession, .airpods):
            String(localized: "Headphone motion is preferred; iPhone will be used if it becomes unavailable.")
        case (.preSession, .iPhone):
            String(localized: "Selected automatically when the session starts.")
        case (.preSession, nil):
            String(localized: "Check Apple Watch, headphone, or iPhone motion availability.")
        case (.activeSession, .watch):
            String(localized: "This session cannot switch to iPhone after it starts.")
        case (.activeSession, .airpods), (.activeSession, .iPhone), (.activeSession, nil):
            String(localized: "The motion source is managed automatically during this iPhone session.")
        }
    }

    /// Returns the connected headphone model when available, with the shared source name as a stable fallback.
    private var displayName: String {
        guard source == .airpods,
              let connectedHeadphoneName,
              !connectedHeadphoneName.isEmpty
        else {
            return source?.shortName ?? String(localized: "Motion source")
        }

        return connectedHeadphoneName
    }
}

#Preview("Before Session") {
    MotionSourceStatusView(
        source: .watch,
        connectedHeadphoneName: "AirPods Pro",
        presentation: .preSession
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Active Session") {
    MotionSourceStatusView(
        source: .airpods,
        connectedHeadphoneName: "AirPods Pro",
        presentation: .activeSession
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
