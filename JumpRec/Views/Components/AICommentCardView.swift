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

    /// Triggers the discrete sparkle animation each time the card transitions from
    /// a loading placeholder into a finished AI summary.
    @State private var sparkleAnimationTrigger = 0

    // MARK: - View

    /// Renders either the finished comment or a loading placeholder.
    var body: some View {
        Group {
            if let comment {
                card {
                    Label {
                        Text(comment)
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } icon: {
                        sparklesIcon
                    }
                }
            } else if isLoading {
                card {
                    HStack(spacing: 12) {
                        ProgressView()
                            .tint(AppColors.accent)
                        Text("Writing your session comment...")
                            .font(AppFonts.bodyLabel)
                            .foregroundStyle(AppColors.textSecondary)
                        Spacer()
                    }
                }
            }
        }
        .onAppear(perform: {
            if comment != nil {
                sparkleAnimationTrigger += 1
            }
        })
        .onChange(of: isLoading) { _, _ in
            if !isLoading {
                sparkleAnimationTrigger += 1
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

    // MARK: - Private Helpers

    /// Applies the sparkle symbol styling and replays the completion animation
    /// using the most expressive symbol effect available on the current OS.
    @ViewBuilder
    private var sparklesIcon: some View {
        let sparkles = Image(systemName: "sparkles")
            .font(AppFonts.sectionTitle)
            .foregroundStyle(AppColors.accent)

        if #available(iOS 26.0, *) {
            sparkles
                .symbolEffect(
                    .drawOn.byLayer,
                    options: .speed(0.5),
                    isActive: sparkleAnimationTrigger == 0
                )
        } else {
            sparkles
                .symbolEffect(.bounce, value: sparkleAnimationTrigger)
        }
    }
}

/// Provides an interactive preview that mimics the async AI generation flow.
/// The delayed state change makes it easy to verify both the loading placeholder
/// and the completion animation without running the full app.
private struct AICommentCardDelayedPreview: View {
    @State private var comment: String?
    @State private var isLoading = true

    var body: some View {
        AICommentCardView(comment: comment, isLoading: isLoading)
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AppColors.bgPrimary)
            .task {
                guard comment == nil else { return }
                try? await Task.sleep(for: .seconds(2))
                comment = "Your pacing stayed impressively steady, and the final stretch showed strong control with very few breaks."
                isLoading = false
            }
    }
}

#Preview("Delayed Comment") {
    AICommentCardDelayedPreview()
        .preferredColorScheme(.dark)
}
