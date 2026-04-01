//
//  TimerView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
//

import SwiftUI

/// Displays a high-frequency timer for the active watch workout.
struct TimerView: View {
    /// The time when the current session started.
    let startTime: Date

    /// Creates a timer view anchored to a specific start time.
    init(startTime: Date) {
        self.startTime = startTime
    }

    /// Renders the continuously updating elapsed time.
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            let diff = timeline.date.timeIntervalSince(startTime)
            Text(diff.minutesSecondsMilliseconds)
                .font(AppFonts.watchTimer)
                .foregroundStyle(AppColors.textSecondary)
        }
    }
}

extension TimeInterval {
    /// Formats a time interval as `mm:ss.d` for live display.
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
