//
//  StartView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import Combine
import JumpRecShared
import SwiftUI

struct StartView: View {
    @State var isCountingDown: Bool = false
    @State var isAnimating: Bool = false
    @State var countdown: Double = 3
    var timer = Timer.publish(every: 1, on: .main, in: .common)
    var onStart: () -> Void

    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    @State var showSettings: Bool = false

    var goal: Text {
        switch settings.goalType {
        case .count:
            return Text("\(settings.jumpCount.formatted()) jumps")
        case .time:
            return Text("\(settings.jumpTime) min")
        @unknown default:
            return Text("\(settings.jumpCount.formatted()) jumps")
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                if isCountingDown {
                    ZStack {
                        Text("\(countdown, specifier: "%.0f")")
                            .font(.system(size: 48, weight: .bold, design: .monospaced))
                            .foregroundStyle(AppColors.textPrimary)
                            .onReceive(timer.autoconnect()) { _ in
                                countdown -= 1
                            }
                        Circle()
                            .trim(from: 0, to: isAnimating ? 1 : 0)
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
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
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
                                .font(.system(size: 11))
                            goal
                                .font(.system(size: 12, weight: .medium))
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
