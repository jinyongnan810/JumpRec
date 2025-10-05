//
//  TimerView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

struct TimerView: View {
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

#Preview {
    TimerView(startTime: Date())
}
