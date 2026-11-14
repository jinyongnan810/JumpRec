//
//  JumpRecShared.swift
//  JumpRecShared
//
//  Created by kinn on 2025/09/13.
//

import Foundation

/// Formats a jump-rate value with the localized per-minute unit.
public nonisolated func localizedRateText(_ value: Int) -> String {
    AppLocalization.rateText(value)
}

/// Formats a normalized score such as `0.92` as a locale-aware percentage for UI display.
public nonisolated func localizedPercentText(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

/// Formats a calorie-efficiency metric for display in a way that can be localized per target.
public nonisolated func localizedCaloriesPerMinuteText(_ value: Double) -> String {
    let formattedValue = value.formatted(.number.precision(.fractionLength(1)))
    return String(
        format: String(localized: "%@ kcal/min"),
        formattedValue
    )
}
