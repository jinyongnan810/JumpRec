//
//  SessionCompleteView.swift
//  JumpRec
//

import SwiftUI

/// Displays the summary screen after a session finishes.
struct SessionCompleteView: View {
    @Environment(MyDataStore.self) private var dataStore

    /// The app state containing the just-completed session details.
    @Bindable var appState: JumpRecState
    /// Resets the flow back to the idle state.
    var onDone: () -> Void

    /// Controls the completion badge's one-time entrance animation.
    @State private var isCompletionBadgeVisible = false
    /// Reveals completion sections in order, independently of the badge animation.
    @State private var hasContentAppeared = false
    /// Tracks the visible recap request even while background generation is pending.
    @State private var isGeneratingComment = false

    // MARK: - Derived Values

    /// Returns the saved session object when one is available.
    private var completedSession: JumpSession? {
        appState.completedSession
    }

    /// Includes the debug CSV button in the entrance sequence only when visible.
    private var hasMotionCSVShareAction: Bool {
        #if DEBUG
            return appState.motionCSVShareURL != nil
        #else
            return false
        #endif
    }

    /// Uses the saved session or a temporary summary while persistence is pending.
    private var summarySession: JumpSession {
        if let completedSession {
            return completedSession
        }

        let durationSeconds = max(appState.durationSeconds, 1)
        let startTime = appState.startTime ?? .now
        let session = JumpSession(
            startedAt: startTime,
            endedAt: startTime.addingTimeInterval(TimeInterval(durationSeconds)),
            jumpCount: appState.jumpCount,
            peakRate: 0,
            averageRate: Double(appState.averageRate),
            caloriesBurned: appState.caloriesBurned,
            smallBreaksCount: appState.breakMetrics.small,
            longBreaksCount: appState.breakMetrics.long,
            longestStreak: appState.breakMetrics.longestStreak,
            averageHeartRate: appState.averageHeartRate,
            peakHeartRate: appState.peakHeartRate
        )
        let temporaryRateSamples = SessionMetricsCalculator.makeRateSamples(
            jumpOffsets: appState.jumps,
            durationSeconds: durationSeconds
        )
        session.replaceRateSamples(with: temporaryRateSamples)
        session.peakRate = SessionMetricsCalculator.peakRate(from: temporaryRateSamples)
        return session
    }

    /// The exact personal record kinds that are still waiting to be acknowledged by the user.
    private var unseenRecordKinds: [PersonalRecordKind] {
        dataStore.unseenPersonalRecordKinds
    }

    // MARK: - View

    /// Renders the post-session summary, chart, and actions.
    var body: some View {
        // Create one fallback session per render and share its samples and analytics.
        let summary = summarySession
        let samples = summary.decodedRateSamples
        let metrics = summary.derivedMetrics(rateSamples: samples)
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(AppColors.accent)
                            .frame(width: 64, height: 64)
                            .scaleEffect(isCompletionBadgeVisible ? 1 : 0.6)
                            .opacity(isCompletionBadgeVisible ? 1 : 0)
                        completionCheckmark
                    }
                    // Play the delayed badge spring once when the screen appears.
                    .onAppear {
                        guard !isCompletionBadgeVisible else { return }
                        withAnimation(.spring(response: 1, dampingFraction: 1)) {
                            isCompletionBadgeVisible = true
                        }
                    }
                    Text("Workout Complete!")
                        .font(AppFonts.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Here are your results.")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }
                // .staggeredAppearance(isVisible: hasContentAppeared, index: 0)

                if let completedSession,
                   SessionAICommentGenerator.shouldGenerate(for: completedSession)
                {
                    AICommentCardView(
                        comment: completedSession.aiComment,
                        isLoading: isGeneratingComment
                    )
                    .staggeredAppearance(isVisible: hasContentAppeared, index: 1)
                }

                SessionMetricsSummaryView(
                    duration: summary.formattedDuration,
                    jumps: summary.formattedJumpCount,
                    calories: summary.formattedCalories,
                    averageRate: summary.formattedAverageRate(),
                    peakRate: summary.formattedPeakRate(),
                    rhythmConsistency: metrics.rhythmConsistency.map { localizedPercentText($0) } ?? "--",
                    caloriesPerMinute: metrics.caloriesPerMinute.map { localizedCaloriesPerMinuteText($0) } ?? "--",
                    longestJumpStrikes: summary.formattedLongestStreak,
                    shortBreaks: summary.formattedSmallBreaksCount,
                    longBreaks: summary.formattedLongBreaksCount,
                    averageHeartRate: summary.formattedAverageHeartRate(),
                    peakHeartRate: summary.formattedPeakHeartRate(),
                    rateSamples: samples,
                    achievedRecordKinds: unseenRecordKinds
                )
                .staggeredAppearance(isVisible: hasContentAppeared, index: 2)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
                #if DEBUG
                    if let motionCSVShareURL = appState.motionCSVShareURL {
                        ShareLink(item: motionCSVShareURL) {
                            HStack(spacing: 8) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(AppFonts.sectionIcon)
                                Text("SHARE CSV")
                                    .font(AppFonts.cardTitle)
                            }
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                        }
                        .appGlassButton(prominent: false)
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 3)
                    }
                #endif

                // Done Button
                Button(action: onDone) {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark")
                            .font(AppFonts.sectionIcon)
                        Text("DONE")
                            .font(AppFonts.cardTitle)
                    }
                    .foregroundStyle(AppColors.bgPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                }
                .appGlassButton(
                    prominent: true,
                    tint: AppColors.accent
                )
                .staggeredAppearance(
                    isVisible: hasContentAppeared,
                    index: hasMotionCSVShareAction ? 4 : 3
                )
            }.padding(.horizontal, 24)
        }
        .task {
            // Wait one update cycle to render hidden sections before revealing them.
            await Task.yield()
            hasContentAppeared = true
        }
        .task(id: completedSession?.id) {
            guard !isGeneratingComment, completedSession != nil else { return }
            await generateCommentIfNeeded()
        }
    }

    // MARK: - Actions

    /// Requests the saved session's recap and tracks loading while this screen is visible.
    private func generateCommentIfNeeded() async {
        guard let completedSession else { return }
        guard SessionAICommentGenerator.shouldGenerate(for: completedSession) else { return }
        guard completedSession.aiComment == nil else { return }
        guard SessionAICommentGenerator.isAvailable else { return }

        isGeneratingComment = true
        _ = await dataStore.generateAICommentIfNeeded(for: completedSession)
        isGeneratingComment = false
    }

    // MARK: - Private Subviews

    /// Uses line-drawing animation where supported, with a bounce fallback.
    @ViewBuilder
    private var completionCheckmark: some View {
        let checkmark = Image(systemName: "checkmark")
            .font(AppFonts.largeDisplay)
            .foregroundStyle(AppColors.bgPrimary)

        if #available(iOS 26.0, *) {
            checkmark
                .foregroundStyle(.white)
                .symbolEffect(
                    .drawOn,
                    options: .speed(0.5),
                    isActive: !isCompletionBadgeVisible
                )
        } else {
            checkmark
                .symbolEffect(.bounce, value: isCompletionBadgeVisible)
                .scaleEffect(isCompletionBadgeVisible ? 1 : 0.2)
                .opacity(isCompletionBadgeVisible ? 1 : 0)
        }
    }
}

#Preview {
    let dataStore = MyDataStore.shared
    let appState = JumpRecState()
    let start = Calendar.current.date(byAdding: .minute, value: -8, to: Date())!
    let end = Date()
    let session = JumpSession(
        startedAt: start,
        endedAt: end,
        jumpCount: 1248,
        peakRate: 176,
        averageRate: 156,
        caloriesBurned: 214,
        smallBreaksCount: 4,
        longBreaksCount: 1,
        longestStreak: 286,
        averageHeartRate: 148,
        peakHeartRate: 176,
        aiComment: "Strong control through the middle section. You kept a high cadence, limited long breaks, and finished with a consistent rhythm."
    )

    let sampleData: [(Int, Double)] = [
        (0, 92), (30, 118), (60, 136), (90, 152),
        (120, 164), (150, 171), (180, 176), (210, 168),
        (240, 160), (270, 156), (300, 150), (330, 158),
        (360, 154), (390, 146), (420, 138), (450, 132),
    ]

    session.replaceRateSamples(
        with: sampleData.map { secondOffset, rate in
            RateSamplePoint(secondOffset: secondOffset, rate: Float(rate))
        }
    )

    appState.sessionState = .complete
    appState.startTime = start
    appState.endTime = end
    appState.jumpCount = session.jumpCount
    appState.jumps = sampleData.map { TimeInterval($0.0) }
    appState.caloriesBurned = session.caloriesBurned
    appState.averageHeartRate = session.averageHeartRate
    appState.peakHeartRate = session.peakHeartRate
    appState.completedSession = session
    #if DEBUG
        appState.motionCSVShareURL = URL(fileURLWithPath: "/tmp/jumprec-preview-motion.csv")
    #endif

    dataStore.markUnseenPersonalRecordUpdates([.highestJumpCount, .steadyRhythm, .sneakyBurn])

    return SessionCompleteView(appState: appState, onDone: {})
        .environment(dataStore)
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
