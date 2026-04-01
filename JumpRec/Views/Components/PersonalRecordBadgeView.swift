//
//  PersonalRecordBadgeView.swift
//  JumpRec
//

import SwiftUI

/// A compact badge that surfaces newly achieved personal records.
/// The glowing dot gives the badge a subtle shimmer so it feels noticeable without being noisy.
struct PersonalRecordBadgeView: View {
    enum Style {
        case compact
        case pill
    }

    enum AnimationMode {
        case continuous
        case once
        case none
    }

    let style: Style
    var animationMode: AnimationMode = .continuous

    @State private var isAnimating = false

    private var shouldAnimate: Bool {
        animationMode != .none
    }

    var body: some View {
        HStack(spacing: style == .pill ? 6 : 0) {
            shiningDot

            if style == .pill {
                Text("New Record")
                    .font(AppFonts.badgeLabel)
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
        .padding(.horizontal, style == .pill ? 10 : 5)
        .padding(.vertical, style == .pill ? 6 : 5)
        .background(
            Capsule()
                .fill(AppColors.cardSurface.opacity(style == .pill ? 1 : 0.9))
        )
        .overlay(
            Capsule()
                .stroke(AppColors.accent.opacity(0.35), lineWidth: 1)
        )
        .shadow(color: AppColors.accent.opacity(0.18), radius: style == .pill ? 10 : 6)
        .onAppear {
            guard shouldAnimate else { return }

            switch animationMode {
            case .continuous:
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true)) {
                    isAnimating = true
                }
            case .once:
                withAnimation(.easeOut(duration: 2)) {
                    isAnimating = true
                }
            case .none:
                break
            }
        }
        .onDisappear {
            guard animationMode == .once else { return }
            // Reset one-shot badges so they can replay when a new unseen-record state appears.
            isAnimating = false
        }
    }

    /// A glowing dot with a tiny highlight to imply a polished "shine" effect.
    private var shiningDot: some View {
        ZStack {
            Circle()
                .fill(AppColors.accent.opacity(0.22))
                .frame(width: 14, height: 14)
                .scaleEffect(haloScale)

            Circle()
                .fill(AppColors.accent)
                .frame(width: 7, height: 7)
                .shadow(color: AppColors.accent.opacity(0.9), radius: glowRadius)

            Circle()
                .fill(Color.white.opacity(0.95))
                .frame(width: 2.5, height: 2.5)
                .offset(x: -1.8, y: -1.8)
                .opacity(highlightOpacity)
        }
        .frame(width: 14, height: 14)
    }

    private var haloScale: CGFloat {
        if !shouldAnimate {
            return 1
        }

        switch animationMode {
        case .continuous:
            return isAnimating ? 1.35 : 0.85
        case .once:
            return isAnimating ? 1.15 : 0.7
        case .none:
            return 1
        }
    }

    private var glowRadius: CGFloat {
        if !shouldAnimate {
            return 4
        }

        switch animationMode {
        case .continuous:
            return isAnimating ? 7 : 3
        case .once:
            return isAnimating ? 6 : 2
        case .none:
            return 4
        }
    }

    private var highlightOpacity: Double {
        if !shouldAnimate {
            return 0.85
        }

        switch animationMode {
        case .continuous:
            return isAnimating ? 1 : 0.65
        case .once:
            return isAnimating ? 1 : 0.5
        case .none:
            return 0.85
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        PersonalRecordBadgeView(style: .pill)
        PersonalRecordBadgeView(style: .compact)
        PersonalRecordBadgeView(style: .compact, animationMode: .once)
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
}
