//
//  TopSoftScrollEdgeEffect.swift
//  JumpRec
//

import SwiftUI

extension View {
    /// Applies the softer iOS 27 scroll-edge treatment to content that scrolls beneath a top navigation bar.
    ///
    /// The modifier is intentionally a no-op on older iOS versions so call sites can keep a single,
    /// readable modifier chain without duplicating the surrounding view structure for availability checks.
    @ViewBuilder
    func topSoftScrollEdgeEffect() -> some View {
        if #available(iOS 27.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
