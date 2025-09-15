//
//  JumpRecApp.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import JumpRecShared
import SwiftUI

@main
struct JumpRec_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(JumpRecSettings())
        }
    }
}
