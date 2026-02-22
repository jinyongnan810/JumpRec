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
    // doesn't work
    @Query() var sessions: [JumpSession]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [.cyan, .blue],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            List(sessions) { session in
                Text("start: \(session.startedAt), end: \(session.endedAt)")
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
        }
        .padding()
    }
}

#Preview {
    ContentView()
        .environment(MyDataStore.shared)
}
