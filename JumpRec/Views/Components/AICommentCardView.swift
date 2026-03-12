//
//  AICommentCardView.swift
//  JumpRec
//

import SwiftUI

struct AICommentCardView: View {
    let comment: String?
    let isLoading: Bool

    var body: some View {
        if let comment {
            card {
                Label {
                    Text(comment)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } icon: {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.accent)
                }
            }
        } else if isLoading {
            card {
                HStack(spacing: 12) {
                    ProgressView()
                        .tint(AppColors.accent)
                    Text("Writing your session comment...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func card(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(AppColors.cardSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(AppColors.accent.opacity(0.2), lineWidth: 1)
            )
    }
}
