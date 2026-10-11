//
//  TimerView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/10/05.
//

import SwiftUI

/// Displays an elapsed workout timer for the active watch workout using system low-power rendering.
struct TimerView: View {
    /// The time when the current session started.
    let startTime: Date

    /// Creates a timer view anchored to a specific start time.
    init(startTime: Date) {
        self.startTime = startTime
    }

    /// Renders elapsed time with system timer text, without a SwiftUI update timer.
    var body: some View {
        Text(startTime, style: .timer)
            .font(AppFonts.watchTimer)
            .foregroundStyle(AppColors.textSecondary)
            .accessibilityLabel(Text("Elapsed time"))
    }
}

#Preview {
    TimerView(startTime: Date())
}
