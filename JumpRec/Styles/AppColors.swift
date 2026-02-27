//
//  AppColors.swift
//  JumpRec
//

import SwiftUI

extension Color {
    init(hex: UInt, alpha: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

enum AppColors {
    static let bgPrimary = Color(hex: 0x0A0F1C)
    static let cardSurface = Color(hex: 0x1E293B)
    static let accent = Color(hex: 0x22D3EE)
    static let textPrimary = Color.white
    static let textSecondary = Color(hex: 0x94A3B8)
    static let textMuted = Color(hex: 0x64748B)
    static let tabInactive = Color(hex: 0x475569)
}
