//
//  StatCardView.swift
//  JumpRec
//

import SwiftUI

struct StatCardView: View {
    let label: String
    let value: String
    var valueColor: Color = AppColors.textPrimary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            Text(value)
                .font(.system(size: 20, weight: .bold, design: .monospaced))
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(AppColors.cardSurface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

#Preview {
    HStack(spacing: 10) {
        StatCardView(label: "TIME", value: "04:32")
        StatCardView(label: "CALORIES", value: "86")
        StatCardView(label: "RATE", value: "128/m", valueColor: AppColors.accent)
    }
    .padding()
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
