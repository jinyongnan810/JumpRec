//
//  GlassSlider.swift
//  SwiftUIPractices
//
//  Created by Yuunan kin on 2026/07/12.
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

    /// Reads the standard SwiftUI environment `isEnabled` state to hide the interactive slider thumb icon when disabled.
    @Environment(\.isEnabled) private var isEnabled

    @State private var offset: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let sliderWidth = proxy.size.width

            ZStack(alignment: .leading) {
                trackBackground

                ZStack(alignment: .leading) {
                    Text(text)
                        .font(.title)
                        .foregroundStyle(config.tint.secondary)

                    // The moving mask gives the label a subtle shimmer while keeping
                    // the base text visible for legibility on every supported OS.
                    Text(text)
                        .font(.title)
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

                // Hide the interactive thumb icon when the slider is disabled so users clearly see
                // that sliding is unavailable (e.g. when mirroring an Apple Watch session).
                if isEnabled {
                    Image(systemName: iconName)
                        .foregroundStyle(config.tint)
                        .font(.title)
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
        // Liquid Glass is only available on iOS 26 and newer. The fallback keeps
        // the same capsule silhouette and soft translucent feel so the control
        // still reads as a slider on older deployment targets.
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
        // Keep the OS-specific modifier isolated so the main slider layout does
        // not need to duplicate drag handling or text rendering for availability.
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
            text: "STOP SESSION",
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
