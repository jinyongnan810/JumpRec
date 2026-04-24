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

    /// Drives the one-time entrance animation for the completion badge.
    /// Keeping this state local makes the animation deterministic for this screen
    /// without coupling it to broader session lifecycle state.
    @State private var isCompletionBadgeVisible = false
    /// Tracks whether this screen is actively requesting an AI recap for the just-finished session.
    /// The completion flow can arrive before the background generation task has finished, so the
    /// view keeps its own loading flag to show a deterministic placeholder instead of inferring
    /// progress from the current comment text alone.
    @State private var isGeneratingComment = false

    // MARK: - Derived Values

    /// Returns the saved session object when one is available.
    private var completedSession: JumpSession? {
        appState.completedSession
    }

    /// Provides one session-shaped value for all summary calculations on this screen.
    /// When persistence has not finished yet, we synthesize a temporary session so the
    /// summary UI still uses the exact same formatting and derived-metric logic.
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

    /// Returns rate samples for the saved session or generated temporary summary session.
    ///
    /// The completion screen displays the chart immediately after a workout, so decoding or reading
    /// the in-memory rate-series payload here is expected and separate from lazy history loading.
    /// The calculator generates points chronologically, so no extra per-render sorting is needed.
    private var rateSamples: [RateSamplePoint] {
        summarySession.decodedRateSamples
    }

    /// Returns the shared derived metrics used across summary surfaces.
    private var derivedMetrics: JumpSession.DerivedMetrics {
        summarySession.derivedMetrics(rateSamples: rateSamples)
    }

    /// The exact personal record kinds that are still waiting to be acknowledged by the user.
    private var unseenRecordKinds: [PersonalRecordKind] {
        dataStore.unseenPersonalRecordKinds
    }

    // MARK: - View

    /// Renders the post-session summary, chart, and actions.
    var body: some View {
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
                    // The delayed spring gives the completion icon a clear "arrival"
                    // moment when this screen is pushed into view, while avoiding a
                    // repeated animation during unrelated body updates.
                    .onAppear {
                        guard !isCompletionBadgeVisible else { return }
                        withAnimation(.spring(response: 1, dampingFraction: 1)) {
                            isCompletionBadgeVisible = true
                        }
                    }
                    Text("Session Complete!")
                        .font(AppFonts.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Text("Here are your results.")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }

                if let completedSession,
                   SessionAICommentGenerator.shouldGenerate(for: completedSession)
                {
                    AICommentCardView(
                        comment: completedSession.aiComment,
                        isLoading: isGeneratingComment
                    )
                }

                SessionMetricsSummaryView(
                    duration: durationText,
                    jumps: jumpCountText,
                    calories: caloriesText,
                    averageRate: averageRateText,
                    peakRate: peakRateText,
                    rhythmConsistency: rhythmConsistencyText,
                    caloriesPerMinute: caloriesPerMinuteText,
                    longestJumpStrikes: longestStreakText,
                    shortBreaks: shortBreaksText,
                    longBreaks: longBreaksText,
                    averageHeartRate: averageHeartRateText,
                    peakHeartRate: peakHeartRateText,
                    rateSamples: rateSamples,
                    achievedRecordKinds: unseenRecordKinds
                )
            }
            .padding(.horizontal, 24)
        }
        .scrollIndicators(.hidden)
        .padding(.horizontal, 24)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 12) {
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
                }

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
            }.padding(.horizontal, 24)
        }
        .task(id: completedSession?.id) {
            guard !isGeneratingComment, completedSession != nil else { return }
            await generateCommentIfNeeded()
        }
    }

    // MARK: - Formatting

    /// Returns the completed session duration text.
    private var durationText: String {
        summarySession.formattedDuration
    }

    /// Returns the formatted jump-count text.
    private var jumpCountText: String {
        summarySession.formattedJumpCount
    }

    /// Returns the formatted calories text.
    private var caloriesText: String {
        summarySession.formattedCalories
    }

    /// Returns the formatted average-rate text.
    private var averageRateText: String {
        summarySession.formattedAverageRate()
    }

    /// Returns the formatted peak-rate text.
    private var peakRateText: String {
        summarySession.formattedPeakRate()
    }

    /// Returns the formatted rhythm-consistency text.
    private var rhythmConsistencyText: String {
        guard let rhythmConsistency = derivedMetrics.rhythmConsistency else { return "--" }
        return localizedPercentText(rhythmConsistency)
    }

    /// Returns the formatted calories-per-minute text.
    private var caloriesPerMinuteText: String {
        guard let caloriesPerMinute = derivedMetrics.caloriesPerMinute else { return "--" }
        return localizedCaloriesPerMinuteText(caloriesPerMinute)
    }

    /// Returns the formatted longest-streak text.
    private var longestStreakText: String {
        summarySession.formattedLongestStreak
    }

    /// Returns the formatted short-break count.
    private var shortBreaksText: String {
        summarySession.formattedSmallBreaksCount
    }

    /// Returns the formatted long-break count.
    private var longBreaksText: String {
        summarySession.formattedLongBreaksCount
    }

    /// Returns the formatted average heart-rate text.
    private var averageHeartRateText: String {
        summarySession.formattedAverageHeartRate()
    }

    /// Returns the formatted peak heart-rate text.
    private var peakHeartRateText: String {
        summarySession.formattedPeakHeartRate()
    }

    // MARK: - Actions

    /// Ensures the completion screen actively requests an AI recap for the saved session.
    /// The session save path already attempts generation in the background, but this view still
    /// performs an explicit check so the UI owns its loading state and reliably refreshes when the
    /// comment becomes available while the summary screen is visible.
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

    /// Chooses the symbol animation style based on OS support.
    /// Newer systems get the line-drawing treatment, while earlier releases keep
    /// the bounce fallback so the completion state still feels celebratory.
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
    appState.motionCSVShareURL = URL(fileURLWithPath: "/tmp/jumprec-preview-motion.csv")

    dataStore.markUnseenPersonalRecordUpdates([.highestJumpCount, .steadyRhythm, .sneakyBurn])

    return SessionCompleteView(appState: appState, onDone: {})
        .environment(dataStore)
        .background(AppColors.bgPrimary)
        .preferredColorScheme(.dark)
}
