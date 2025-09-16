//
//  JumpCountView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/14.
//

import Combine
import JumpRecShared
import SwiftUI

let TimeString = "Time"
let MinuteString = "Minute"

struct JumpCountView: View {
    @State var motionManager = MotionManager()
    @Environment(JumpRecSettings.self)
    private var settings: JumpRecSettings
    @State var showSettings: Bool = false
    @State var startTime: Date = .init()

    var goal: Text {
        switch settings.goalType {
        case .count:
            return Text("^[\(settings.jumpCount) \(TimeString)](inflect: true)")
        case .time:
            return Text("^[\(settings.jumpTime) \(MinuteString)](inflect: true)")
        @unknown default:
            return Text("^[\(settings.jumpCount) \(TimeString)](inflect: true)")
        }
    }

    var body: some View {
        NavigationStack {
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
                    VStack {
                        Spacer()
                        HStack {
                            TimeCountView(startTime: startTime)
                            Spacer()
                        }
                    }
                }.onTapGesture {
                    WKInterfaceDevice.current().play(.stop)
                    DispatchQueue.main.async {
                        motionManager.stopTracking()
                    }
                }
            } else {
                StartView(motionManager: $motionManager, startTime: $startTime)
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button(action: {
                                showSettings.toggle()
                            }) {
                                Image(systemName: "gearshape.fill")
                            }
                        }
                    }
                    .navigationTitle(goal)
                    .navigationDestination(isPresented: $showSettings) {
                        GoalView()
                    }
            }
        }
    }
}

struct StartView: View {
    @State var isCountingDown: Bool = false
    @State var countdown: Double = 3
    @Binding var motionManager: MotionManager
    @Binding var startTime: Date
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
                    startTime = Date()
                    withAnimation {
                        isCountingDown.toggle()
                    }
                }
        }
    }
}

struct TimeCountView: View {
    let startTime: Date
    let calendar = Calendar.current
    init(startTime: Date) {
        self.startTime = startTime
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let diff = timeline.date.timeIntervalSince(startTime)
            Text(
                diff.minutesSecondsMilliseconds
            )
        }
    }
}

extension TimeInterval {
    var minutesSecondsMilliseconds: String {
        let totalSeconds = Int(self)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let milliseconds = Int(truncatingRemainder(dividingBy: 1) * 10)

        return String(format: "%02d:%02d.%01d", minutes, seconds, milliseconds)
    }
}
