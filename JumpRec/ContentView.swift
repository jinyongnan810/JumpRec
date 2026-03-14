//
//  ContentView.swift
//  JumpRec
//
//  Created by Yuunan kin on 2025/09/13.
//

import StoreKit
import SwiftData
import SwiftUI
import UIKit

struct ContentView: View {
    @Environment(MyDataStore.self) var dataStore
    @Environment(\.requestReview) private var requestReview
    @AppStorage("hasRequestedReviewAfterTenSessions") private var hasRequestedReviewAfterTenSessions = false
    @State private var connectivityManager = ConnectivityManager.shared
    @Query() var sessions: [JumpSession]

    @State private var selectedTab: Tab = .jump
    @State private var settings = JumpRecSettings()
    @State private var appState = JumpRecState()
    @State private var pendingReviewTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            AppColors.bgPrimary.ignoresSafeArea()

            TabView(selection: $selectedTab) {
                HomeView(
                    settings: settings,
                    appState: appState,
                    isWatchAvailable: connectivityManager.isPaired &&
                        connectivityManager.isWatchAppInstalled,
                    watchUnavailableReason: watchUnavailableReason
                ) {
                    appState.start(goalType: settings.goalType, goalValue: settings.goalCount)
                }
                .tabItem {
                    Label("Jump", systemImage: "figure.jumprope")
                }
                .tag(Tab.jump)

                HistoryView()
                    .tabItem {
                        Label("History", systemImage: "chart.bar.fill")
                    }
                    .tag(Tab.history)
            }
            .tint(AppColors.accent)
            .toolbarVisibility(appState.sessionState == .idle ? .visible : .hidden, for: .tabBar)
        }
        .fullScreenCover(isPresented: isSessionFlowPresented) {
            Group {
                switch appState.sessionState {
                case .active:
                    ActiveSessionView(settings: settings, appState: appState) {
                        appState.finish()
                    }
                case .complete:
                    SessionCompleteView(appState: appState) {
                        appState.reset()
                    }
                case .idle:
                    EmptyView()
                }
            }
        }
        .preferredColorScheme(.dark)
        .onAppear {
//            configureTabBarAppearance()
            syncSettingsToWatch()
        }
        .onChange(of: settings.goalType) { _, _ in
            syncSettingsToWatch()
        }
        .onChange(of: settings.jumpCount) { _, _ in
            syncSettingsToWatch()
        }
        .onChange(of: settings.jumpTime) { _, _ in
            syncSettingsToWatch()
        }
        .onChange(of: appState.completedSession?.id) { _, _ in
            scheduleReviewRequestIfNeeded()
        }
        .onChange(of: sessions.count) { _, _ in
            scheduleReviewRequestIfNeeded()
        }
    }

    private var isSessionFlowPresented: Binding<Bool> {
        Binding(
            get: { appState.sessionState != .idle },
            set: { isPresented in
                if !isPresented {
                    appState.reset()
                }
            }
        )
    }

    private var watchUnavailableReason: String {
        if !connectivityManager.isPaired {
            return String(localized: "Apple Watch is unavailable because no paired watch was found.")
        }
        if !connectivityManager.isWatchAppInstalled {
            return String(localized: "Apple Watch is unavailable because the JumpRec Watch app is not installed.")
        }
        return String(localized: "Apple Watch is ready.")
    }

//    private func configureTabBarAppearance() {
//        let appearance = UITabBarAppearance()
//        appearance.configureWithDefaultBackground()
//
//        let normalAttributes: [NSAttributedString.Key: Any] = [
//            .font: UIFont.systemFont(ofSize: 16, weight: .medium),
//        ]
//        let selectedAttributes: [NSAttributedString.Key: Any] = [
//            .font: UIFont.systemFont(ofSize: 16, weight: .semibold),
//        ]
//
//        appearance.stackedLayoutAppearance.normal.titleTextAttributes = normalAttributes
//        appearance.stackedLayoutAppearance.selected.titleTextAttributes = selectedAttributes
//        appearance.inlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
//        appearance.inlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes
//        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = normalAttributes
//        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = selectedAttributes
//
//        UITabBar.appearance().standardAppearance = appearance
//        UITabBar.appearance().scrollEdgeAppearance = appearance
//    }

    private func syncSettingsToWatch() {
        connectivityManager.syncSettings(
            goalType: settings.goalType,
            jumpCount: settings.jumpCount,
            jumpTime: settings.jumpTime
        )
    }

    private func scheduleReviewRequestIfNeeded() {
        guard appState.sessionState == .complete,
              appState.completedSession != nil,
              sessions.count >= 10,
              !hasRequestedReviewAfterTenSessions
        else {
            pendingReviewTask?.cancel()
            pendingReviewTask = nil
            return
        }

        pendingReviewTask?.cancel()
        pendingReviewTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, appState.sessionState == .complete else { return }
            await requestReview()
            hasRequestedReviewAfterTenSessions = true
            pendingReviewTask = nil
        }
    }
}

#Preview {
    ContentView()
        .environment(MyDataStore.shared)
}
