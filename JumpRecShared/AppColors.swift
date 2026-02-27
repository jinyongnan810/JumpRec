//
//  AppColors.swift
//  JumpRecShared
//

import SwiftUI

public extension Color {
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

public enum AppColors {
    public static let bgPrimary = Color(hex: 0x0A0F1C)
    public static let cardSurface = Color(hex: 0x1E293B)
    public static let accent = Color(hex: 0x22D3EE)
    public static let textPrimary = Color.white
    public static let textSecondary = Color(hex: 0x94A3B8)
    public static let textMuted = Color(hex: 0x64748B)
    public static let tabInactive = Color(hex: 0x475569)
    public static let danger = Color(hex: 0xFF4444)
    public static let warning = Color(hex: 0xF59E0B)
    public static let heartRate = Color(hex: 0xEF4444)
}
