//
//  GlassSlider.swift
//  SwiftUIPractices
//
//  Created by kinn on 2026/07/12.
//

import SwiftUI

struct GlassSlider: View {
    let text: String
    let iconName: String
    let config: Config

    struct Config {
        var tint: Color
        var size: CGFloat = 100
    }

    let onProgressChanged: (CGFloat) -> Void
    let onFinished: () -> Void

    /// Hides the slider thumb when the SwiftUI environment disables interaction.
    @Environment(\.isEnabled) private var isEnabled

    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let sliderWidth = proxy.size.width

            ZStack(alignment: .leading) {
                trackBackground

                ZStack(alignment: .leading) {
                    Text(text)
                        .font(AppFonts.sectionTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(config.tint.secondary)

                    // Animate a shimmer mask while keeping the base label readable.
                    Text(text)
                        .font(AppFonts.sectionTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .foregroundStyle(config.tint)
                        .mask(alignment: .leading) {
                            GeometryReader { proxy in
                                let size = proxy.size
                                let maskWidth: CGFloat = 50
                                let width: CGFloat = size.width + maskWidth

                                Rectangle()
                                    .frame(width: 15)
                                    .blur(radius: 5)
                                    .rotationEffect(.degrees(12))
                                    .offset(x: -maskWidth)
                                    .keyframeAnimator(
                                        initialValue: CGFloat.zero,
                                        repeating: true
                                    ) { content, offset in
                                        content.offset(x: offset)
                                    } keyframes: { _ in
                                        LinearKeyframe(width, duration: 3)
                                    }
                            }
                        }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Hide the thumb when sliding is disabled.
                if isEnabled {
                    Image(systemName: iconName)
                        .foregroundStyle(config.tint)
                        .font(AppFonts.sectionTitle)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: config.size, height: config.size)
                        .modifier(SliderThumbGlassEffect())
                        .offset(x: offset)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let maxOffset = max(sliderWidth - config.size, 0)
                                    let cappedOffset = min(max(value.translation.width, 0), maxOffset)

                                    offset = cappedOffset
                                    onProgressChanged(maxOffset == 0 ? 0 : cappedOffset / maxOffset)
                                }
                                .onEnded { value in
                                    let maxOffset = max(sliderWidth - config.size, 0)
                                    let cappedOffset = min(max(value.translation.width, 0), maxOffset)

                                    if maxOffset > 0, cappedOffset >= maxOffset {
                                        onFinished()
                                        return
                                    }

                                    withAnimation {
                                        offset = 0
                                    }
                                }
                        )
                }
            }
        }
        .frame(height: config.size)
    }

    // MARK: - Private subviews

    @ViewBuilder
    private var trackBackground: some View {
        // Use Liquid Glass on iOS 26 and a translucent capsule on older versions.
        if #available(iOS 26.0, *) {
            Capsule()
                .fill(config.tint.opacity(0.05))
                .glassEffect(.regular)
        } else {
            Capsule()
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule()
                        .fill(config.tint.opacity(0.05))
                }
                .overlay {
                    Capsule()
                        .stroke(config.tint.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

private struct SliderThumbGlassEffect: ViewModifier {
    func body(content: Content) -> some View {
        // Apply the available glass style without duplicating the slider layout.
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.clear, in: .circle)
        } else {
            content
                .background {
                    Circle()
                        .fill(.ultraThinMaterial)
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.35), lineWidth: 1)
                }
        }
    }
}

#Preview {
    VStack(spacing: 24) {
        GlassSlider(
            text: "STOP WORKOUT",
            iconName: "stop.fill",
            config: GlassSlider.Config(tint: .red, size: 80),
            onProgressChanged: { _ in },
            onFinished: {}
        )

        GlassSlider(
            text: "STOP ON WATCH",
            iconName: "stop.fill",
            config: GlassSlider.Config(tint: .gray, size: 80),
            onProgressChanged: { _ in },
            onFinished: {}
        )
        .disabled(true)
    }
    .padding(24)
    .background(Color.black)
}
