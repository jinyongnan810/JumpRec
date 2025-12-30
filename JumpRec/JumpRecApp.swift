//
//  JumpRecApp.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/13.
//

import JumpRecShared
import SwiftData
import SwiftUI

@main
struct JumpRecApp: App {
    @State private var dataStore = MyDataStore.shared
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(dataStore.modelContainer)
                .environment(dataStore)
        }
    }
}
