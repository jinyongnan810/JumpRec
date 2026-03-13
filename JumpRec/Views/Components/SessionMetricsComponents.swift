//
//  SessionMetricsComponents.swift
//  JumpRec
//

import SwiftUI

struct SessionMetricCard: View {
    let label: LocalizedStringKey
    let value: String
    var valueColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct SessionBreakdownRow<Content: View>: View {
    let label: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            content
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
