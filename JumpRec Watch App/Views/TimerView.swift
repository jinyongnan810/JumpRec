//
//  TimerView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/10/05.
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

    /// Renders the continuously updating elapsed time using system compositor rendering.
    ///
    /// Using `Text(_:style: .timer)` lets watchOS handle counter updates in the system compositor
    /// without waking SwiftUI view bodies, string allocations, or CPU timers every 100ms.
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
