//
//  JumpRecShared.swift
//  JumpRecShared
//
//  Created by Yuunan kin on 2025/09/13.
//

import Foundation

public func localizedRateText(_ value: Int) -> String {
    if Locale.preferredLanguages.first?.hasPrefix("ja") == true {
        return "\(value)/分"
    }
    return "\(value)/min"
}
