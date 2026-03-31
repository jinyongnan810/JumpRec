//
//  JumpRecShared.swift
//  JumpRecShared
//
//  Created by Yuunan kin on 2025/09/13.
//

import Foundation

public extension Locale {
    /// Returns whether Japanese is the preferred system language.
    static var isJapanesePreferredLanguage: Bool {
        preferredLanguages.first?.hasPrefix("ja") == true
    }
}

public func localizedRateText(_ value: Int) -> String {
    if Locale.isJapanesePreferredLanguage {
        return "\(value)/分"
    }
    return "\(value)/min"
}

/// Formats a normalized score such as `0.92` as a locale-aware percentage for UI display.
public func localizedPercentText(_ value: Double) -> String {
    value.formatted(.percent.precision(.fractionLength(0)))
}

/// Formats a calorie-efficiency metric for display in a way that can be localized per target.
public func localizedCaloriesPerMinuteText(_ value: Double) -> String {
    let formattedValue = value.formatted(.number.precision(.fractionLength(1)))
    return String(
        format: String(localized: "%@ kcal/min"),
        formattedValue
    )
}
