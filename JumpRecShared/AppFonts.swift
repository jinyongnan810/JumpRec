//
//  AppFonts.swift
//  JumpRecShared
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

/// Centralizes every custom font choice used by the app so typography can be
/// adjusted in one place without hunting through individual views.
public enum AppFonts {
    // MARK: - Helpers

    /// Builds a standard system font while keeping the sizing details in this
    /// shared catalog instead of scattering them across views.
    public static func system(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        design: Font.Design = .default
    ) -> Font {
        .system(size: size, weight: weight, design: design)
    }

    /// Builds a monospaced system font for countdowns, metrics, and any other
    /// numeric content that benefits from stable glyph widths.
    public static func monospaced(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        system(size, weight: weight, design: .monospaced)
    }

    /// Builds a rounded system font for the few places where the UI intentionally
    /// uses a softer, more playful presentation.
    public static func rounded(
        _ size: CGFloat,
        weight: Font.Weight = .regular
    ) -> Font {
        system(size, weight: weight, design: .rounded)
    }

    // MARK: - Shared iPhone Fonts

    public static let screenTitle = system(24, weight: .semibold)
    public static let screenTitleRegular = system(24)
    public static let heroRingValue = rounded(48, weight: .bold)
    public static let heroRingSubtitle = system(12, weight: .medium)
    public static let primaryButtonLabel = system(15, weight: .semibold)
    public static let secondaryActionLabel = system(13, weight: .medium)
    public static let bodyLabel = system(14, weight: .medium)
    public static let bodyLabelStrong = system(15, weight: .medium)
    public static let bodySmall = system(13)
    public static let bodyRegular = system(14)
    public static let sectionTitle = system(18, weight: .semibold)
    public static let sectionIcon = system(18)
    public static let cardTitle = system(15, weight: .semibold)
    public static let badgeLabel = system(11, weight: .semibold)
    public static let eyebrowLabel = system(10, weight: .semibold)
    public static let iconLabel = system(11)
    public static let badgeIconLabel = system(13, weight: .semibold)
    public static let smallValue = system(12, weight: .semibold)
    public static let smallValueMonospaced = monospaced(12, weight: .semibold)
    public static let smallActionLabel = system(14, weight: .semibold)
    public static let largeControlIcon = system(22)
    public static let detailValue = system(16, weight: .semibold)
    public static let largeDisplay = system(28, weight: .bold)
    public static let metricValueMonospaced = monospaced(20, weight: .bold)
    public static let metricValueLargeMonospaced = monospaced(22, weight: .bold)
    public static let metricValueXLMonospaced = monospaced(32, weight: .bold)
    public static let statValueMonospaced = monospaced(18, weight: .bold)
    public static let supportingMonospaced = monospaced(11)
    public static let metricDetailMonospaced = monospaced(13, weight: .semibold)
    public static let graphAxisMonospaced = monospaced(10, weight: .medium)
    public static let graphLabelMonospaced = monospaced(10, weight: .semibold)
    public static let calendarBadgeMonospaced = monospaced(8, weight: .semibold)

    /// The calendar switches weight to indicate selection state, so the shared
    /// catalog exposes a parameterized font instead of duplicating the logic in
    /// the view layer.
    public static func calendarDay(weight: Font.Weight) -> Font {
        monospaced(12, weight: weight)
    }

    // MARK: - Watch Fonts

    public static let watchCountdown = monospaced(48, weight: .bold)
    public static let watchPrimaryButton = monospaced(20, weight: .bold)
    public static let watchGoalValue = monospaced(28, weight: .bold)
    public static let watchResultValue = monospaced(36, weight: .bold)
    public static let watchMetricValue = monospaced(40, weight: .bold)
    public static let watchMetricLabel = monospaced(10, weight: .semibold)
    public static let watchMetricDetail = monospaced(14, weight: .medium)
    public static let watchMetricDetailBold = monospaced(14, weight: .bold)
    public static let watchMetricCompact = monospaced(12, weight: .bold)
    public static let watchTimer = monospaced(14, weight: .medium)
    public static let watchGoalLabel = system(12, weight: .medium)
    public static let watchGoalChip = rounded(12, weight: .medium)
    public static let watchSectionTitle = system(15, weight: .semibold)
    public static let watchBody = system(12)
    public static let watchBodySmall = system(10)
    public static let watchBodyTiny = system(9, weight: .medium)
    public static let watchSupporting = system(11)
    public static let watchSupportingRegular = system(14)

    // MARK: - Live Activity Fonts

    public static let liveActivityCaption = Font.caption
    public static let liveActivityCaption2 = Font.caption2
    public static let liveActivityCaptionSemibold = Font.caption.weight(.semibold)
    public static let liveActivityHeadline = Font.headline
    public static let liveActivityTimer = Font.title3.monospacedDigit()

    #if canImport(UIKit)
    // MARK: - UIKit Fonts

    /// Provides UIKit counterparts for the few controls whose typography still
    /// has to be configured through appearance APIs.
    public static func uiSystem(
        _ size: CGFloat,
        weight: UIFont.Weight = .regular
    ) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: weight)
    }

    public static let segmentedControlLabel = uiSystem(15, weight: .semibold)
    #endif
}
