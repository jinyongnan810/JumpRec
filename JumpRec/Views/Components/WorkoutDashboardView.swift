import SwiftUI

/// Keeps workout progress and actions readable as the available space changes.
struct WorkoutDashboardView<Progress: View, Controls: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var isWorkoutActive: Bool
    @ViewBuilder var progress: (CGFloat) -> Progress
    @ViewBuilder var controls: () -> Controls

    var body: some View {
        GeometryReader { geometry in
            if #available(iOS 27.1, *),
               horizontalSizeClass == .regular || !geometry.reservedRegions(kind: .division).isEmpty
            {
                // The system keeps each pane clear of the fold, including in tabletop poses.
                ArrangementView {
                    WorkoutProgressPane(progress: progress)
                } secondary: {
                    GeometryReader { pane in
                        ScrollView {
                            controls()
                                .frame(maxWidth: 440)
                                .frame(maxWidth: .infinity)
                                .padding(24)
                                .frame(minHeight: pane.size.height)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .arrangementViewStyle(.split)
            } else {
                let isHorizontal = geometry.size.width > geometry.size.height && !dynamicTypeSize.isAccessibilitySize
                let layout = isHorizontal ? AnyLayout(HStackLayout(spacing: 24)) : AnyLayout(VStackLayout(spacing: 24))
                let availableWidth = isHorizontal ? (geometry.size.width - 72) / 2 : geometry.size.width - 48
                let availableHeight = isHorizontal ? max(120, geometry.size.height - 66) : 270
                let diameter = max(0, min(270, min(availableWidth - 18, availableHeight)))
                let topSpacing = isHorizontal ? 0 : diameter / (isWorkoutActive ? 6 : 2)

                ScrollView {
                    layout {
                        progress(diameter)
                            .frame(maxWidth: .infinity)
                        controls()
                            .frame(maxWidth: 440)
                            .frame(maxWidth: .infinity)
                    }
                    // Keep the ring's position independent of the controls' height.
                    .padding(.top, topSpacing)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: isWorkoutActive)
                    .padding(24)
                    .frame(minHeight: geometry.size.height, alignment: isHorizontal ? .center : .top)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct WorkoutProgressPane<Progress: View>: View {
    @ViewBuilder var progress: (CGFloat) -> Progress

    var body: some View {
        GeometryReader { geometry in
            let diameter = max(0, min(360, min(geometry.size.width, geometry.size.height) - 66))
            progress(diameter)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
