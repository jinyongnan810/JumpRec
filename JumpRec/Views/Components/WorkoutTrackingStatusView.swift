import SwiftUI

/// Makes the active sensor source visible when the phone is used as a workout display.
struct WorkoutTrackingStatusView: View {
    let source: DeviceSource?

    var body: some View {
        if let source {
            VStack(spacing: 8) {
                Label(title(for: source), systemImage: source.iconName)
                    .font(AppFonts.bodyLabelStrong)
                    .foregroundStyle(AppColors.accent)
                    .multilineTextAlignment(.center)

                if source == .iPhone {
                    Text("Keep iPhone in your pocket to detect jumps.")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func title(for source: DeviceSource) -> LocalizedStringResource {
        switch source {
        case .watch: "Tracking on Apple Watch"
        case .airpods: "Tracking with headphones"
        case .iPhone: "Tracking with iPhone"
        }
    }
}
