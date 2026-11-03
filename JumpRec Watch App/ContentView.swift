//
//  ContentView.swift
//  JumpRec Watch App
//
//  Created by kinn on 2025/09/13.
//

import SwiftUI

struct ContentView: View {
    @State private var connectivityMangaer = ConnectivityManager.shared

    var body: some View {
        MainView()
            .tint(AppColors.accent)
    }
}

#Preview {
    ContentView()
        .environment(JumpRecSettings())
}

#if DEBUG
    #Preview("10 Free Workouts Used") {
        // Tapping Start in this idle preview shows quota help.
        ContentView()
            .environment(JumpRecSettings(previewQualifiedWorkoutCount: JumpRecSettings.freeWorkoutQuota))
    }
#endif
