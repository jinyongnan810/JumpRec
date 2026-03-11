//
//  DeviceSelectorView.swift
//  JumpRec
//

import SwiftUI

struct DeviceSelectorView: View {
    let activeSource: DeviceSource?
    let isPhoneMotionAvailable: Bool
    let isHeadphoneMotionAvailable: Bool
    let isWatchMotionAvailable: Bool
    let watchUnavailableReason: String

    @State private var infoMessage: String?
    @State private var dismissTask: Task<Void, Never>?

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
                    availabilityBadge(for: .iPhone, isAvailable: isPhoneMotionAvailable)
                    availabilityBadge(for: .airpods, isAvailable: isHeadphoneMotionAvailable)
                }
            }
        }
        .overlay(alignment: .center) {
            if let infoMessage {
                infoBanner(message: infoMessage)
                    .padding(.horizontal, 8)
                    .offset(y: 56)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: infoMessage)
    }

    private var activeSourceCard: some View {
        let source = activeSource

        return HStack(spacing: 14) {
            Image(systemName: source?.iconName ?? "sensor.tag.radiowaves.forward")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(source?.shortName ?? "Searching")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)

                Text(source == nil ? "No motion source connected yet" : "Currently selected for motion data")
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
        .accessibilityLabel("Active source")
        .accessibilityValue(source?.shortName ?? "Searching")
    }

    @ViewBuilder
    private func availabilityBadge(for source: DeviceSource, isAvailable: Bool) -> some View {
        let isActive = activeSource == source
        let message = unavailableMessage(for: source)

        Group {
            if isAvailable || isActive {
                badgeLabel(for: source, isAvailable: isAvailable, isActive: isActive)
            } else {
                Button {
                    showInfo(message)
                } label: {
                    badgeLabel(for: source, isAvailable: isAvailable, isActive: isActive)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows why this device is unavailable")
            }
        }
    }

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

    private func infoBanner(message: String) -> some View {
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
        .background(AppColors.cardSurface.opacity(0.92))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .stroke(AppColors.warning.opacity(0.35), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func badgeForeground(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.bgPrimary
        }
        if isAvailable {
            return AppColors.textSecondary
        }
        return AppColors.textMuted
    }

    private func badgeBackground(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.accent
        }
        if isAvailable {
            return AppColors.cardSurface.opacity(0.9)
        }
        return AppColors.cardSurface.opacity(0.45)
    }

    private func badgeStroke(isAvailable: Bool, isActive: Bool) -> Color {
        if isActive {
            return AppColors.accent
        }
        if isAvailable {
            return AppColors.textMuted.opacity(0.4)
        }
        return AppColors.textMuted.opacity(0.2)
    }

    private func badgeAccessibilityValue(isAvailable: Bool, isActive: Bool) -> String {
        if isActive {
            return "Active"
        }
        if isAvailable {
            return "Available"
        }
        return "Unavailable"
    }

    private func unavailableMessage(for source: DeviceSource) -> String {
        switch source {
        case .watch:
            watchUnavailableReason
        case .iPhone:
            "iPhone motion is not available on this device."
        case .airpods:
            "Headphone motion is unavailable. Connect supported AirPods or Beats and allow motion access."
        }
    }

    private func showInfo(_ message: String) {
        dismissTask?.cancel()
        infoMessage = message
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation {
                    infoMessage = nil
                }
            }
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
