//
//  ContentView.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/13.
//

import JumpRecShared
import SwiftData
import SwiftUI

struct ContentView: View {
    @Environment(MyDataStore.self) var dataStore
    @State private var connectivityManager = ConnectivityManager.shared
    @State private var headphoneManager = HeadphoneManager()
    // doesn't work
    @Query() var sessions: [JumpSession]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            VStack {
                Text(
                    verbatim: "Watch connected: \(connectivityManager.isPaired && connectivityManager.isWatchAppInstalled)"
                )
                Text(
                    verbatim: "Headphones connected: \(headphoneManager.motionActive)"
                )
                List(sessions) { session in
                    let startString = session.startedAt.formatted(date: .abbreviated, time: .shortened)
                    let endString = session.endedAt.formatted(date: .abbreviated, time: .shortened)
                    Text(verbatim: "start: \(startString), end: \(endString)")
                }
            }
        }
        .onChange(of: sessions) { _, newValue in
            print("🔥sessions: \(newValue)")
        }
        .onAppear {
            do {
                let results = try dataStore.modelContext.fetch(FetchDescriptor<JumpSession>())
                print("⭐️fetched results count: \(results.count)")
                for result in results {
                    print(
                        "⭐️fetched: \(result.startedAt),\(result.endedAt),\(result.jumpCount),\(result.caloriesBurned)"
                    )
                    print("details: \(result.details?.jumps)")
                }
            } catch {
                print("failed to fetch: \(error)")
            }
            headphoneManager.start()
        }
        .onDisappear(perform: {
            headphoneManager.stop()
        })
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(MyDataStore.shared)
}
