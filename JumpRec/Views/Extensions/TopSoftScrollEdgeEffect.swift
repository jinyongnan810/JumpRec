//
//  TopSoftScrollEdgeEffect.swift
//  JumpRec
//

import SwiftUI

extension View {
    /// Uses soft top scroll edges on iOS 27; leaves older versions unchanged.
    @ViewBuilder
    func topSoftScrollEdgeEffect() -> some View {
        if #available(iOS 27.0, *) {
            self.scrollEdgeEffectStyle(.soft, for: .top)
        } else {
            self
        }
    }
}
