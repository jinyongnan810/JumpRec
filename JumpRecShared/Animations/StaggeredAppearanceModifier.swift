//
//  StaggeredAppearanceModifier.swift
//  JumpRecShared
//

import SwiftUI

/// Applies a reusable fade-and-rise entrance treatment with an ordered delay.
///
/// The delay is capped so large collections do not leave later items waiting excessively long.
/// People who enable Reduce Motion receive the final layout immediately without movement or fading.
private struct StaggeredAppearanceModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// Indicates whether the view should display its final visible state.
    let isVisible: Bool
    /// Determines this view's position within the staggered entrance sequence.
    let index: Int

    /// Limits the total stagger while preserving the visual ordering of the first visible items.
    private var delay: TimeInterval {
        min(Double(index) * 0.055, 0.44)
    }

    func body(content: Content) -> some View {
        content
            .opacity(accessibilityReduceMotion || isVisible ? 1 : 0)
            .offset(y: accessibilityReduceMotion || isVisible ? 0 : 14)
            .animation(
                isVisible && !accessibilityReduceMotion
                    ? .easeOut(duration: 0.38).delay(delay)
                    : nil,
                value: isVisible
            )
    }
}

public extension View {
    /// Adds an ordered fade-and-rise entrance animation using the view's sequence position.
    ///
    /// - Parameters:
    ///   - isVisible: Set to `true` to reveal the view using the staggered animation.
    ///   - index: The zero-based position used to calculate the view's entrance delay.
    func staggeredAppearance(isVisible: Bool, index: Int) -> some View {
        modifier(StaggeredAppearanceModifier(isVisible: isVisible, index: index))
    }
}
