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
    /// Remembers the previous loading state so the view can react only to the
    /// completion edge instead of animating during every refresh.
    @State private var previousLoadingState: Bool?
    /// Holds a pending sparkle animation when loading finishes before the final
    /// comment text has appeared in the hierarchy.
    @State private var shouldAnimateSparklesWhenCommentAppears = false

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
        // Capture the initial loading state so a preloaded comment does not animate
        // on first render unless it actually finished generating while this view was visible.
        .onAppear {
            if previousLoadingState == nil {
                previousLoadingState = isLoading
            }
            triggerPendingSparklesIfNeeded()
        }
        .onChange(of: isLoading) { _, newValue in
            defer { previousLoadingState = newValue }

            guard previousLoadingState == true, newValue == false else { return }
            shouldAnimateSparklesWhenCommentAppears = true
            triggerPendingSparklesIfNeeded()
        }
        .onChange(of: comment) { _, _ in
            triggerPendingSparklesIfNeeded()
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
                    .drawOn,
                    options: .speed(0.5),
                    isActive: sparkleAnimationTrigger == 0
                )
        } else {
            sparkles
                .symbolEffect(.bounce, value: sparkleAnimationTrigger)
        }
    }

    /// Runs the pending sparkle animation only after the finished comment is visible.
    /// Deferring the trigger this way avoids losing the effect when loading ends and
    /// the text arrives in a separate state update.
    private func triggerPendingSparklesIfNeeded() {
        guard shouldAnimateSparklesWhenCommentAppears, comment != nil else { return }
        shouldAnimateSparklesWhenCommentAppears = false
        sparkleAnimationTrigger += 1
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
