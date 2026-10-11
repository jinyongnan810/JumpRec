//
//  AppFonts.swift
//  JumpRecShared
//

import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif

/// Shared typography for the iPhone app, Watch app, and extensions.
public enum AppFonts {
    // MARK: - Helpers

    /// Creates a system font with a fixed size.
    public static func system(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// Creates a monospaced font with stable widths for numeric content.
    public static func monospaced(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        system(size, weight: weight, design: .monospaced)
    }

    /// Creates a rounded system font.
    public static func rounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        system(size, weight: weight, design: .rounded)
    }

    /// Text styles support Dynamic Type; fixed sizes suit icons and chart geometry.
    private static func text(_ style: Font.TextStyle, weight: Font.Weight = .regular,
                             design: Font.Design = .default) -> Font
    {
        .system(style, design: design).weight(weight)
    }

    // MARK: - Shared iPhone Fonts

    public static let screenTitle = text(.title2, weight: .semibold)
    public static let screenTitleRegular = text(.title2)
    public static let heroRingBaseSize: CGFloat = 60
    public static func heroRingValue(size: CGFloat) -> Font { rounded(size, weight: .bold) }
    public static let heroRingSubtitle = text(.subheadline, weight: .medium)
    public static let primaryButtonLabel = text(.body, weight: .semibold)
    public static let secondaryActionLabel = text(.subheadline, weight: .medium)
    public static let bodyLabel = text(.subheadline, weight: .medium)
    public static let bodyLabelStrong = text(.body, weight: .medium)
    public static let bodySmall = text(.subheadline)
    public static let bodyRegular = text(.subheadline)
    public static let sectionTitle = text(.title3, weight: .semibold)
    public static let sectionIcon = system(18)
    public static let cardTitle = text(.body, weight: .semibold)
    public static let badgeLabel = text(.caption, weight: .semibold)
    public static let eyebrowLabel = text(.caption2, weight: .semibold)
    public static let iconLabel = text(.caption)
    public static let badgeIconLabel = system(13, weight: .semibold)
    public static let smallValue = text(.caption, weight: .semibold)
    public static let smallValueMonospaced = text(.caption, weight: .semibold, design: .monospaced)
    public static let smallActionLabel = text(.subheadline, weight: .semibold)
    public static let largeControlIcon = system(22)
    public static let detailValue = text(.body, weight: .semibold)
    public static let largeDisplay = text(.largeTitle, weight: .bold)
    public static let metricValueMonospaced = text(.title3, weight: .bold, design: .monospaced)
    public static let metricValueLargeMonospaced = text(.title2, weight: .bold, design: .monospaced)
    public static let metricValueXLMonospaced = text(.largeTitle, weight: .bold, design: .monospaced)
    public static let statValueMonospaced = text(.title3, weight: .bold, design: .monospaced)
    public static let supportingMonospaced = text(.caption, design: .monospaced)
    public static let metricDetailMonospaced = text(.subheadline, weight: .semibold, design: .monospaced)
    public static let graphAxisMonospaced = monospaced(10, weight: .medium)
    public static let graphLabelMonospaced = monospaced(10, weight: .semibold)
    public static let calendarBadgeMonospaced = monospaced(8, weight: .semibold)

    /// Uses font weight to indicate calendar selection.
    public static func calendarDay(weight: Font.Weight) -> Font {
        monospaced(12, weight: weight)
    }

    // MARK: - Watch Fonts

    public static let watchCountdownBaseSize: CGFloat = 48
    public static let watchCountdown = monospaced(watchCountdownBaseSize, weight: .bold)
    public static let watchPrimaryButton = text(.title3, weight: .bold, design: .monospaced)
    public static let watchGoalValue = monospaced(28, weight: .bold)
    public static let watchResultValueBaseSize: CGFloat = 36
    public static let watchResultValue = monospaced(watchResultValueBaseSize, weight: .bold)
    public static let watchMetricValueBaseSize: CGFloat = 40
    public static let watchMetricValue = monospaced(watchMetricValueBaseSize, weight: .bold)
    public static let watchMetricLabel = text(.caption2, weight: .semibold, design: .monospaced)
    public static let watchMetricDetail = text(.subheadline, weight: .medium, design: .monospaced)
    public static let watchMetricDetailBold = text(.subheadline, weight: .bold, design: .monospaced)
    public static let watchMetricCompact = text(.caption, weight: .bold, design: .monospaced)
    public static let watchTimer = text(.subheadline, weight: .medium, design: .monospaced)
    public static let watchGoalLabel = text(.caption, weight: .medium)
    public static let watchGoalChip = text(.caption, weight: .medium, design: .rounded)
    public static let watchSectionTitle = text(.body, weight: .semibold)
    public static let watchBody = text(.caption)
    public static let watchBodySmall = text(.caption2)
    public static let watchBodyTiny = text(.caption2, weight: .medium)
    public static let watchSupporting = text(.caption)
    public static let watchSupportingRegular = text(.subheadline)

    // MARK: - Live Activity Fonts

    public static let liveActivityCaption = Font.caption
    public static let liveActivityCaption2 = Font.caption2
    public static let liveActivityCaptionSemibold = Font.caption.weight(.semibold)
    public static let liveActivityHeadline = Font.headline
    public static let liveActivityTimer = Font.title3.monospacedDigit()

    #if canImport(UIKit)

        // MARK: - UIKit Fonts

        /// UIKit fonts for controls configured through appearance APIs.
        public static func uiSystem(
            _ size: CGFloat,
            weight: UIFont.Weight = .regular
        ) -> UIFont {
            UIFont.systemFont(ofSize: size, weight: weight)
        }

        public static let segmentedControlLabel = uiSystem(15, weight: .semibold)
    #endif
}
