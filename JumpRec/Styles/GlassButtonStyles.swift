//
//  GlassButtonStyles.swift
//  JumpRec
//

import SwiftUI

extension View {
    @ViewBuilder
    func appGlassButton(prominent: Bool = false, tint: Color? = nil) -> some View {
        if let tint {
            if #available(iOS 26.0, *) {
                if prominent {
                    self.tint(tint).buttonStyle(.glassProminent)
                } else {
                    self.tint(tint).buttonStyle(.glass)
                }
            } else {
                if prominent {
                    self.tint(tint).buttonStyle(.borderedProminent)
                } else {
                    self.tint(tint).buttonStyle(.bordered)
                }
            }
        } else {
            if #available(iOS 26.0, *) {
                if prominent {
                    self.buttonStyle(.glassProminent)
                } else {
                    self.buttonStyle(.glass)
                }
            } else {
                if prominent {
                    buttonStyle(.borderedProminent)
                } else {
                    buttonStyle(.bordered)
                }
            }
        }
    }
}
