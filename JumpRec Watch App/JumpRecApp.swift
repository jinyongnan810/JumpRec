//
//  JumpRecApp.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import JumpRecShared
import SwiftData
import SwiftUI

@main
struct JumpRec_Watch_AppApp: App {
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
