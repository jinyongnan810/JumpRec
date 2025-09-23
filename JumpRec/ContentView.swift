//
//  ContentView.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/13.
//

import SwiftUI

struct ContentView: View {
    @State private var connectivityManager = ConnectivityManager.shared
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Hello, world!")
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
