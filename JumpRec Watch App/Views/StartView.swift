//
//  StartView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import Combine
import SwiftUI

/// Displays the watch start screen and pre-session countdown.
struct StartView: View {
    /// Indicates whether the countdown is currently showing.
    @State var isCountingDown: Bool = false
    /// Drives the countdown ring animation.
    @State var isAnimating: Bool = false
    /// Stores the current countdown value.
    @State var countdown: Double = 3
    /// Publishes countdown ticks once per second.
    var timer = Timer.publish(every: 1, on: .main, in: .common)
    /// Starts the workout when the countdown finishes.
    var onStart: () -> Void

    /// Provides the currently selected workout goal.
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    /// Controls navigation to the goal settings screen.
    @State var showSettings: Bool = false

    /// Returns the formatted goal text shown under the start button.
    var goal: Text {
        switch settings.goalType {
        case .count:
            return Text(
                String(
                    format: String(localized: "%@ jumps"),
                    settings.jumpCount.formatted()
                )
            )
        case .time:
            return Text(
                String(
                    format: String(localized: "%lld min"),
                    settings.jumpTime
                )
            )
        @unknown default:
            return Text(
                String(
                    format: String(localized: "%@ jumps"),
                    settings.jumpCount.formatted()
                )
            )
        }
    }

    /// Renders the start screen or active countdown.
    var body: some View {
        NavigationStack {
            ZStack {
                if isCountingDown {
                    ZStack {
                        Text("\(countdown, specifier: "%.0f")")
                            .font(AppFonts.watchCountdown)
                            .foregroundStyle(AppColors.textPrimary)
                            .contentTransition(.numericText())
                            .onReceive(timer.autoconnect()) { _ in
                                withAnimation {
                                    countdown -= 1
                                }
                            }
                        Circle()
                            .trim(from: 0, to: isAnimating ? 0 : 1)
                            .stroke(
                                style: .init(
                                    lineWidth: 8,
                                    lineCap: .round
                                )
                            )
                            .foregroundStyle(AppColors.accent)
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(
                                duration: 3.0
                            ), value: isAnimating)
                    }
                    .onAppear {
                        withAnimation {
                            isAnimating = true
                        } completion: {
                            onStart()
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Text("START")
                            .font(AppFonts.watchPrimaryButton)
                            .tracking(2)
                            .foregroundStyle(AppColors.bgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(AppColors.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onTapGesture {
                                withAnimation {
                                    isCountingDown.toggle()
                                }
                            }

                        HStack(spacing: 4) {
                            Image(systemName: "target")
                                .font(AppFonts.watchSupporting)
                            goal
                                .font(AppFonts.watchGoalLabel)
                        }
                        .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, 8)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        showSettings.toggle()
                    }) {
                        Image(systemName: "gearshape.fill")
                            .foregroundStyle(AppColors.textMuted)
                    }
                }
            }
            .navigationDestination(isPresented: $showSettings) {
                GoalView()
            }
        }
    }
}

#Preview {
    StartView(onStart: {})
        .environment(JumpRecSettings())
}
