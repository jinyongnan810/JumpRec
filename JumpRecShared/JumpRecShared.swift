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
