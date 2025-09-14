//
//  JumpCountView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/14.
//

import Combine
import SwiftUI

struct JumpCountView: View {
    @State var motionManager = MotionManager()
    var body: some View {
        if motionManager.isTracking {
            ZStack {
                VStack {
                    Text("Jumps:")
                        .font(.headline)
                    Spacer()
                }
                VStack {
                    Spacer()
                    Text("\(motionManager.jumpCount)")
                        .font(.largeTitle)
                    Spacer()
                }
            }.onTapGesture {
                WKInterfaceDevice.current().play(.stop)
                DispatchQueue.main.async {
                    motionManager.stopTracking()
                }
            }
        } else {
            StartView(motionManager: $motionManager)
        }
    }
}

struct StartView: View {
    @State var isCountingDown: Bool = false
    @State var countdown: Double = 3
    @Binding var motionManager: MotionManager
    var timer = Timer.publish(every: 1, on: .main, in: .common)
    var body: some View {
        if isCountingDown {
            Text("\(countdown, specifier: "%.0f")")
                .font(.largeTitle)
                .onReceive(timer.autoconnect()) { _ in
                    countdown -= 1
                    if countdown < 0 {
                        DispatchQueue.main.async {
                            WKInterfaceDevice.current().play(.start)
                            motionManager.startTracking()
                        }
                    }
                }
        } else {
            Text("Start")
                .font(.largeTitle)
                .onTapGesture {
                    withAnimation {
                        isCountingDown.toggle()
                    }
                }
        }
    }
}

#Preview {
    JumpCountView()
}
