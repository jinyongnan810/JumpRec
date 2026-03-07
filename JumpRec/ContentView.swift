//
//  ContentView.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/13.
//

import JumpRecShared
import SwiftData
import SwiftUI
import UIKit

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

            TabView(selection: $selectedTab) {
                HomeView(settings: settings) {
                    sessionState = .active
                }
                .tabItem {
                    Label("Home", systemImage: "house.fill")
                }
                .tag(Tab.home)

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "chart.bar.fill")
                    }
                    .tag(Tab.history)
            }
            .tint(AppColors.accent)
            .toolbarVisibility(sessionState == .idle ? .visible : .hidden, for: .tabBar)
        }
        .fullScreenCover(isPresented: isSessionFlowPresented) {
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
                    EmptyView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
            configureTabBarAppearance()
        }
    }

    private var isSessionFlowPresented: Binding<Bool> {
        Binding(
            get: { sessionState != .idle },
            set: { isPresented in
                if !isPresented {
                    sessionState = .idle
                }
            }
        )
    }

    private func configureTabBarAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()

        let normalAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
        ]
        let selectedAttributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
        ]

        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }
}

#Preview {
    ContentView()
        .environment(MyDataStore.shared)
}
