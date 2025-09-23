//
//  ContentView.swift
//  JumpRec Watch App
//
//  Created by Yuunan kin on 2025/09/13.
//

import SwiftUI

struct ContentView: View {
    @State private var connectivityMangaer = ConnectivityManager.shared
    var body: some View {
        JumpCountView()
    }
}

#Preview {
    ContentView()
}
