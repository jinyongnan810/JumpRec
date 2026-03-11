//
//  JumpRecApp.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import HealthKit
import JumpRecShared
import SwiftData
import SwiftUI
import WatchKit

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        guard workoutConfiguration.activityType == .jumpRope else { return }
        JumpRecState.shared.startFromCompanion()
    }
}

@main
struct JumpRec_Watch_AppApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var appDelegate
    @State private var dataStore = MyDataStore.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(JumpRecSettings())
                .modelContainer(dataStore.modelContainer)
                .environment(dataStore)
        }
    }
}
