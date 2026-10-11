//
//  ContentView.swift
//  JumpRec
//
//  Created by kinn on 2025/09/13.
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
    @State private var purchaseManager = PurchaseManager.shared
    @State private var showPaywall = false

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
                        startWorkout(goalType: settings.goalType, goalValue: settings.goalCount)
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
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .preferredColorScheme(.dark)
        .onAppear {
            appState.updateSceneActive(scenePhase == .active)
            // Warm up speech on first appearance to reduce the first workout cue's delay.
            appState.warmUpSpeechSynthesizerIfNeeded()
            dataStore.refreshCloudDiagnostics()
            refreshQuotaAndEntitlements()
            syncSettingsToWatch()
            processPendingIntentStartIfNeeded()
        }
        .onChange(of: scenePhase) { _, newValue in
            appState.updateSceneActive(newValue == .active)
            if newValue == .active {
                dataStore.refreshCloudDiagnostics()
                refreshQuotaAndEntitlements()
                syncSettingsToWatch()
                processPendingIntentStartIfNeeded()
            }
        }
        .onChange(of: dataStore.qualifiedWorkoutCount) { _, count in
            settings.qualifiedWorkoutCount = count
            syncSettingsToWatch()
        }
        .onChange(of: appState.requestedStartGoal) { _, _ in
            processPendingIntentStartIfNeeded()
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
            refreshQuotaAndEntitlements()
            syncSettingsToWatch()
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

    /// Stores the qualifying-session review counter locally; reinstalling resets it.
    private func recordQualifiedCompletedSessionIfNeeded() {
        guard let completedSession = appState.completedSession else { return }

        // Only workouts with at least 100 jumps count toward a review request.
        guard completedSession.jumpCount > 99 else { return }
        qualifiedFinishedSessionCount += 1
    }

    /// Applies settings to the active iPhone session and sends them to Watch.
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

    /// Refreshes entitlements and quota; an unlimited license skips the database count.
    private func refreshQuotaAndEntitlements() {
        let isUnlimited = purchaseManager.hasUnlockedUnlimitedWorkouts
        settings.hasUnlockedUnlimitedWorkouts = isUnlimited

        // Only query SQLite to count qualified workouts if the user is on the free tier.
        if !isUnlimited {
            settings.qualifiedWorkoutCount = dataStore.qualifiedSessionsCount()
        }
    }

    private func syncSettingsToWatch() {
        connectivityManager.syncSettings(
            goalType: settings.goalType,
            jumpCount: settings.jumpCount,
            jumpTime: settings.jumpTime,
            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage,
            hasUnlockedUnlimitedWorkouts: purchaseManager.hasUnlockedUnlimitedWorkouts,
            qualifiedWorkoutCount: settings.qualifiedWorkoutCount
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

    /// Checks quota and preferences at actual start, including after a countdown.
    private func startWorkout(goalType: GoalType, goalValue: Int) {
        guard appState.sessionState == .idle else { return }
        selectedTab = .jump
        guard dataStore.canStartNewWorkout(isLicenseUnlocked: purchaseManager.hasUnlockedUnlimitedWorkouts) else {
            showPaywall = true
            return
        }
        appState.start(
            goalType: goalType,
            goalValue: goalValue,
            preferLocalHeadphonesOverWatch: settings.preferHeadphonesForIPhoneSessions && appState.isHeadphoneMotionAvailable,
            shouldSpeakJumpCountAnnouncements: settings.shouldSpeakJumpCountAnnouncements,
            shouldSpeakJumpTimeAnnouncements: settings.shouldSpeakJumpTimeAnnouncements,
            jumpDetectorThresholdAdjustmentPercentage: settings.jumpDetectorThresholdAdjustmentPercentage
        )
    }

    /// Consumes each intent request once; discards requests during an existing session.
    private func processPendingIntentStartIfNeeded() {
        let request = appState.requestedStartGoal ?? JumpRecState.pendingStartGoal.map {
            JumpRecState.WorkoutStartRequest(type: $0.type, value: $0.value)
        }
        appState.requestedStartGoal = nil
        JumpRecState.pendingStartGoal = nil
        guard let request else { return }
        startWorkout(goalType: request.type, goalValue: request.value)
    }
}

#Preview {
    ContentView()
        .modelContainer(MyDataStore.shared.modelContainer)
        .environment(MyDataStore.shared)
}

#Preview("100 Free Workouts Used") {
    // Seed isolated qualifying sessions so starting a free-tier workout presents the paywall.
    let dataStore = try! MyDataStore.makePreviewStore(qualifiedWorkoutCount: JumpRecSettings.freeWorkoutQuota)
    ContentView()
        .modelContainer(dataStore.modelContainer)
        .environment(dataStore)
}
