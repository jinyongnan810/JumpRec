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
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("hasRequestedReviewAfterTenSessions") private var hasRequestedReviewAfterTenSessions = false
    @AppStorage("qualifiedFinishedSessionCount") private var qualifiedFinishedSessionCount = 0
    @State private var connectivityManager = ConnectivityManager.shared

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
                    onStart: {
                        appState.start(
                            goalType: settings.goalType,
                            goalValue: settings.goalCount,
                            preferLocalHeadphonesOverWatch: settings.preferHeadphonesForIPhoneSessions && appState.isHeadphoneMotionAvailable,
                            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
                            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
                            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage
                        )
                    },
                    onStop: {
                        appState.finish()
                    }
                )
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
        .sheet(isPresented: isSessionCompletePresented) {
            SessionCompleteView(appState: appState) {
                appState.reset()
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationBackground(AppColors.cardSurface)
        }
        .preferredColorScheme(.dark)
        .onAppear {
//            configureTabBarAppearance()
            appState.updateSceneActive(scenePhase == .active)
            // Prime speech once when the root view first appears so the first spoken
            // workout cue does not stall while `AVSpeechSynthesizer` performs its
            // internal one-time initialization work.
            appState.warmUpSpeechSynthesizerIfNeeded()
            dataStore.refreshCloudDiagnostics()
            syncSettingsToWatch()
        }
        .onChange(of: scenePhase) { _, newValue in
            appState.updateSceneActive(newValue == .active)
            if newValue == .active {
                dataStore.refreshCloudDiagnostics()
            }
        }
        .onChange(of: settings.goalType) { _, _ in
            applySettingsChange()
        }
        .onChange(of: settings.jumpCount) { _, _ in
            applySettingsChange()
        }
        .onChange(of: settings.jumpTime) { _, _ in
            applySettingsChange()
        }
        .onChange(of: settings.shouldSpeakJumpCountAnnouncements) { _, _ in
            applySettingsChange()
        }
        .onChange(of: settings.shouldSpeakJumpTimeAnnouncements) { _, _ in
            applySettingsChange()
        }
        .onChange(of: settings.jumpDetectorThresholdAdjustmentPercentage) { _, _ in
            applySettingsChange()
        }
        .onChange(of: appState.completedSession?.id) { _, _ in
            recordQualifiedCompletedSessionIfNeeded()
            scheduleReviewRequestIfNeeded()
        }
    }

    /// Controls presentation of the post-workout summary sheet when a session finishes.
    private var isSessionCompletePresented: Binding<Bool> {
        Binding(
            get: {
                appState.sessionState == .complete
            },
            set: { isPresented in
                if !isPresented {
                    appState.reset() // Called when sheet is dismissed via swipe
                }
            }
        )
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

    /// Persists how many meaningful sessions the user has completed on this installation.
    /// This intentionally uses `AppStorage` rather than querying SwiftData so the root view
    /// does not need to keep the full session table live just to decide when to request a review.
    /// Reinstalling the app resets this counter, which is acceptable for this lightweight heuristic.
    private func recordQualifiedCompletedSessionIfNeeded() {
        guard let completedSession = appState.completedSession else { return }

        // Only workouts with at least 100 jumps count toward the review prompt so accidental
        // starts, warmups, and short test sessions do not quickly exhaust the request threshold.
        guard completedSession.jumpCount > 99 else { return }
        qualifiedFinishedSessionCount += 1
    }

    /// Applies a persisted settings edit to every active consumer.
    ///
    /// Settings can be changed from the active-session sheet, so this helper updates the
    /// running iPhone session first and also sends the latest payload to Apple Watch. When
    /// the current session is mirrored, the phone updates its displayed goal immediately
    /// while the Watch receives the same change through WatchConnectivity.
    private func applySettingsChange() {
        appState.applyActiveSessionSettings(
            goalType: settings.goalType,
            goalValue: settings.goalCount,
            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage
        )
        syncSettingsToWatch()
    }

    private func syncSettingsToWatch() {
        connectivityManager.syncSettings(
            goalType: settings.goalType,
            jumpCount: settings.jumpCount,
            jumpTime: settings.jumpTime,
            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage
        )
    }

    private func scheduleReviewRequestIfNeeded() {
        guard appState.sessionState == .complete,
              appState.completedSession != nil,
              qualifiedFinishedSessionCount >= 10,
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
            requestReview()
            hasRequestedReviewAfterTenSessions = true
            pendingReviewTask = nil
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(MyDataStore.shared.modelContainer)
        .environment(MyDataStore.shared)
}
