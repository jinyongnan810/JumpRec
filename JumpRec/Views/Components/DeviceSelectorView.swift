//
//  DeviceSelectorView.swift
//  JumpRec
//

import SwiftUI

/// Displays the active motion source and availability of each supported device.
struct DeviceSelectorView: View {
    /// The motion source currently being used.
    let activeSource: DeviceSource?
    /// Indicates whether iPhone motion is available.
    let isPhoneMotionAvailable: Bool
    /// Indicates whether headphone motion is available.
    let isHeadphoneMotionAvailable: Bool
    /// Indicates whether watch motion is available.
    let isWatchMotionAvailable: Bool
    /// Explains why watch motion is unavailable.
    let watchUnavailableReason: String

    /// Tracks the unavailable source whose info popover is being shown.
    @State private var presentedInfoSource: DeviceSource?

    // MARK: - View

    /// Renders the active-source summary and availability badges.
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ACTIVE SOURCE")
                .font(.system(size: 11, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            VStack(alignment: .leading, spacing: 10) {
                activeSourceCard

                Text("Automatically switches to the best available device.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)

                HStack(spacing: 8) {
                    availabilityBadge(for: .watch, isAvailable: isWatchMotionAvailable)
                    availabilityBadge(for: .airpods, isAvailable: isHeadphoneMotionAvailable)
                    availabilityBadge(for: .iPhone, isAvailable: isPhoneMotionAvailable)
                }
            }
        }
    }

    // MARK: - Subviews

    /// Displays the currently selected motion source.
    private var activeSourceCard: some View {
        let source = activeSource

        return HStack(spacing: 14) {
            Image(systemName: source?.iconName ?? "sensor.tag.radiowaves.forward")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(source?.shortName ?? String(localized: "Searching"))
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(source == nil ? String(localized: "No motion source connected yet") : String(localized: "Currently selected for motion data"))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(AppColors.cardSurface)
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accent.opacity(0.35), lineWidth: 1.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Active source"))
        .accessibilityValue(source?.shortName ?? String(localized: "Searching"))
    }

    /// Displays a badge for a specific source and optionally explains unavailable states.
    @ViewBuilder
    private func availabilityBadge(for source: DeviceSource, isAvailable: Bool) -> some View {
        let isActive = activeSource == source
        let message = unavailableMessage(for: source)

        Group {
            if isAvailable || isActive {
                badgeLabel(for: source, isAvailable: isAvailable, isActive: isActive)
            } else {
                Button {
                    presentedInfoSource = source
                } label: {
                    badgeLabel(for: source, isAvailable: isAvailable, isActive: isActive)
                }
                .buttonStyle(.plain)
                .popover(
                    isPresented: Binding(
                        get: { presentedInfoSource == source },
                        set: { isPresented in
                            if !isPresented, presentedInfoSource == source {
                                presentedInfoSource = nil
                            }
                        }
                    ),
                    attachmentAnchor: .rect(.bounds),
                    arrowEdge: .bottom
                ) {
                    infoPopover(message: message)
                        .presentationCompactAdaptation(.popover)
                }
                .accessibilityHint(String(localized: "Shows why this device is unavailable"))
            }
        }
    }

    /// Builds the shared badge label styling for a source.
    private func badgeLabel(for source: DeviceSource, isAvailable: Bool, isActive: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: source.iconName)
                .font(.system(size: 13, weight: .semibold))

            Text(source.shortName)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(badgeForeground(isAvailable: isAvailable, isActive: isActive))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(badgeBackground(isAvailable: isAvailable, isActive: isActive))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(badgeStroke(isAvailable: isAvailable, isActive: isActive), lineWidth: 1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.shortName)
        .accessibilityValue(badgeAccessibilityValue(isAvailable: isAvailable, isActive: isActive))
    }

    /// Builds the informational popover shown for unavailable devices.
    private func infoPopover(message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColors.warning)

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 260, alignment: .leading)
    }

    /// Returns the foreground color for a source badge.
    private func badgeForeground(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.bgPrimary
        }
        if isAvailable {
            return AppColors.textSecondary
        }
        return AppColors.textMuted
    }

    /// Returns the background color for a source badge.
    private func badgeBackground(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.accent
        }
        if isAvailable {
            return AppColors.cardSurface.opacity(0.9)
        }
        return AppColors.cardSurface.opacity(0.45)
    }

    /// Returns the outline color for a source badge.
    private func badgeStroke(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.accent
        }
        if isAvailable {
            return AppColors.textMuted.opacity(0.4)
        }
        return AppColors.textMuted.opacity(0.2)
    }

    /// Returns the accessibility value describing a badge state.
    private func badgeAccessibilityValue(isAvailable: Bool, isActive: Bool) -> String {
        if isActive {
            return String(localized: "Active")
        }
        if isAvailable {
            return String(localized: "Available")
        }
        return String(localized: "Unavailable")
    }

    /// Returns the explanatory message for an unavailable source.
    private func unavailableMessage(for source: DeviceSource) -> String {
        switch source {
        case .watch:
            watchUnavailableReason
        case .iPhone:
            String(localized: "iPhone motion is not available on this device.")
        case .airpods:
            String(localized: "Headphone motion is unavailable. Connect supported AirPods or Beats and allow motion access.")
        }
    }
}

#Preview {
    DeviceSelectorView(
        activeSource: .watch,
        isPhoneMotionAvailable: true,
        isHeadphoneMotionAvailable: true,
        isWatchMotionAvailable: true,
        watchUnavailableReason: "Apple Watch is ready."
    )
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
