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
    @Query() var sessions: [JumpSession]

    @State private var selectedTab: Tab = .home
    @State private var settings = JumpRecSettings()
    @State private var sessionState: SessionState = .idle

    var body: some View {
        ZStack {
            AppColors.bgPrimary.ignoresSafeArea()

            VStack(spacing: 0) {
                Group {
                    switch sessionState {
                    case .active:
                        ActiveSessionView(settings: settings) {
                            sessionState = .complete
                        }
                    case .complete:
                        SessionCompleteView {
                            sessionState = .idle
                        }
                    case .idle:
                        switch selectedTab {
                        case .home:
                            HomeView(settings: settings) {
                                sessionState = .active
                            }
                        case .history:
                            Text("History")
                                .foregroundStyle(.white)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if sessionState == .idle {
                    TabBarView(selectedTab: $selectedTab)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
        .environment(MyDataStore.shared)
}
