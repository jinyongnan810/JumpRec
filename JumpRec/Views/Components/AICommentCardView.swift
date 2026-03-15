//
//  AICommentCardView.swift
//  JumpRec
//

import SwiftUI

/// Displays the optional AI-generated recap for a completed session.
struct AICommentCardView: View {
    /// The generated comment text to display when available.
    let comment: String?
    /// Indicates whether a comment is currently being generated.
    let isLoading: Bool

    // MARK: - View

    /// Renders either the finished comment or a loading placeholder.
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

    /// Wraps comment content in the shared card styling.
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
