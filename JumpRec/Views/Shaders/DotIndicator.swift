//
//  DotIndicator.swift
//  JumpRec
//
//  Created by Yuunan kin on 2026/04/07.
//

import SwiftUI

/// Renders the animated shader-based dot treatment used as a decorative status accent.
///
/// The view keeps its own animation timeline so callers can attach it as a lightweight
/// overlay without needing to manage any external state.
struct DotIndicator: View {
    let size: CGFloat
    let color: Color
    private let startDate = Date()

    var body: some View {
        TimelineView(.animation) { context in
            let time = startDate.timeIntervalSince(context.date)
            Rectangle()
                .fill(color)
                .frame(width: size, height: size)
                .visualEffect { content, proxy in
                    content.colorEffect(
                        ShaderLibrary.DotIndicatorShader(
                            .float2(proxy.size),
                            .float(time)
                        )
                    )
                }
                .shadow(color: color.opacity(0.3), radius: size * 0.2)
        }
    }
}

/// Places the shader indicator in the top trailing corner of the modified view.
///
/// Centralizing this layout in one modifier keeps call sites readable and ensures the
/// indicator uses the same overlay alignment and offset everywhere it appears.
private struct DotIndicatorOverlayModifier: ViewModifier {
    let isVisible: Bool
    let size: CGFloat
    let color: Color
    let offset: CGSize

    func body(content: Content) -> some View {
        content.overlay(alignment: .topTrailing) {
            if isVisible {
                DotIndicator(size: size, color: color)
                    .offset(x: offset.width, y: offset.height)
                    .allowsHitTesting(false)
            }
        }
    }
}

extension View {
    /// Adds the animated dot indicator as a decorative top trailing overlay.
    ///
    /// - Parameters:
    ///   - isVisible: Allows common call sites to keep the modifier in place while toggling
    ///     the indicator on and off from local state or derived conditions.
    ///   - size: The rendered size of the square shader surface before masking and glow.
    ///   - color: The tint passed into the shader and matching shadow.
    ///   - offset: Fine-tunes placement relative to the view's top trailing corner.
    /// - Returns: A view with the dot indicator layered above it.
    func dotIndicatorOverlay(
        isVisible: Bool = true,
        size: CGFloat = 100,
        color: Color = .white,
        offset: CGSize = CGSize(width: 30, height: -30)
    ) -> some View {
        modifier(
            DotIndicatorOverlayModifier(
                isVisible: isVisible,
                size: size,
                color: color,
                offset: offset
            )
        )
    }
}

private struct DotIndicatorExample: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.94, green: 0.96, blue: 0.99),
                    Color(red: 0.85, green: 0.89, blue: 0.95),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.16, green: 0.19, blue: 0.26),
                            Color(red: 0.09, green: 0.11, blue: 0.17),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 220, height: 160)
                .dotIndicatorOverlay()
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Inbox")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                        Text("3 unread")
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(20)
                }
                .shadow(color: .black.opacity(0.2), radius: 24, y: 12)
        }
        .navigationTitle("Dot Indicator")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    DotIndicatorExample()
}
