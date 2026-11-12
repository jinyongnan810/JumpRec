//
//  HintPopoverModifier.swift
//  JumpRec
//

import SwiftUI

/// Presents explanatory hint copy inside a compact popover sized to its wrapped text height.
private struct HintPopoverModifier<PopoverContent: View>: ViewModifier {
    /// Controls whether the popover is visible.
    @Binding var isPresented: Bool
    /// Builds the stacked hint copy displayed inside the popover.
    @ViewBuilder let popoverContent: () -> PopoverContent

    // MARK: - View

    /// Attaches a compact popover with a fixed ideal width so multi-line text is not clipped vertically.
    func body(content: Content) -> some View {
        content.popover(isPresented: $isPresented) {
            VStack(alignment: .leading, spacing: 10) {
                popoverContent()
            }
            .padding(16)
            // Compact popovers measure ideal size with an unconstrained width proposal; setting idealWidth
            // ensures text wraps before height is computed rather than clipping at a single-line height.
            .frame(idealWidth: 280, maxWidth: 280, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .presentationCompactAdaptation(.popover)
        }
    }
}

extension View {
    /// Presents a compact hint popover whose height expands to fit multi-line explanatory copy.
    func hintPopover(
        isPresented: Binding<Bool>,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(HintPopoverModifier(isPresented: isPresented, popoverContent: content))
    }
}

#Preview {
    @Previewable @State var isPresented = false

    VStack {
        Text("Double Unders")
            .padding()
            .background(AppColors.cardSurface)
            .hintPopover(isPresented: $isPresented) {
                Text("Double Unders")
                    .font(AppFonts.detailValue)
                    .foregroundStyle(AppColors.textPrimary)

                Text("The number of double-unders detected during your workout. Double-under detection is only available when your workout is recorded with Apple Watch.")
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(AppColors.bgPrimary)
    .preferredColorScheme(.dark)
    .task {
        isPresented = true
    }
}
