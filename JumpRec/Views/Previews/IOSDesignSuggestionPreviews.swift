//
//  IOSDesignSuggestionPreviews.swift
//  JumpRec
//

#if DEBUG
    import SwiftUI

    /// Collects isolated design explorations for the iPhone app.
    ///
    /// These views intentionally do not replace production screens. Keeping the
    /// explorations in one preview-only file makes the proposed hierarchy and
    /// responsive behavior easy to compare before adopting any individual change.
    private struct SuggestedPreviewCanvas<Content: View>: View {
        @ViewBuilder let content: Content

        var body: some View {
            ZStack {
                AppColors.bgPrimary.ignoresSafeArea()
                content
            }
            .preferredColorScheme(.dark)
        }
    }

    /// Demonstrates a home screen where device routing remains visible without
    /// competing with the goal and primary start action.
    private struct SuggestedHomePreview: View {
        var body: some View {
            VStack(spacing: 24) {
                VStack(spacing: 6) {
                    Text("JumpRec")
                        .font(AppFonts.screenTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Button(action: {}) {
                        Label("Goal: 1,000 jumps", systemImage: "target")
                            .font(AppFonts.bodyLabel)
                            .foregroundStyle(AppColors.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                    }
                    .appGlassButton(tint: AppColors.accent)
                }

                Spacer(minLength: 0)

                HeroRingView(
                    progress: 0,
                    centerText: String(localized: "Ready?"),
                    subtitle: String(localized: "Tap Start to begin")
                )

                Spacer(minLength: 0)

                compactDeviceStatus

                Button(action: {}) {
                    Text("START SESSION")
                        .font(AppFonts.primaryButtonLabel)
                        .foregroundStyle(AppColors.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .appGlassButton(prominent: true, tint: AppColors.accent)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }

        /// A one-line status preserves routing confidence while keeping the center
        /// of attention on session readiness and the start button.
        private var compactDeviceStatus: some View {
            HStack(spacing: 10) {
                Image(systemName: "applewatch.radiowaves.left.and.right")
                    .font(AppFonts.sectionIcon)
                    .foregroundStyle(AppColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Apple Watch")
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Text("Ready for this session")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)
                }

                Spacer()

                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.accent)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// Demonstrates a denser live workout layout that keeps all critical metrics
    /// visible on compact phones while retaining a large progress target.
    private struct SuggestedActiveSessionPreview: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(spacing: 18) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ACTIVE SESSION")
                            .font(AppFonts.badgeLabel)
                            .tracking(2)
                            .foregroundStyle(AppColors.textMuted)
                        Text("Goal: 1,000 jumps")
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textPrimary)
                    }

                    Spacer()

                    Label("Watch", systemImage: "applewatch")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(AppColors.cardSurface)
                        .clipShape(Capsule())
                }

                Spacer(minLength: 0)

                HeroRingView(
                    progress: 0.63,
                    centerText: "632",
                    subtitle: "/ 1,000 jumps"
                )

                Spacer(minLength: 0)

                metricsLayout

                VStack(spacing: 6) {
                    Button(action: {}) {
                        Label("STOP SESSION", systemImage: "stop.fill")
                            .font(AppFonts.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                            .frame(maxWidth: .infinity)
                            .frame(height: 56)
                    }
                    .appGlassButton(prominent: true, tint: AppColors.danger)

                    Text("Workout data will be saved before the session closes.")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textMuted)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }

        /// Accessibility sizes switch to a vertical presentation so values remain
        /// readable instead of shrinking inside three narrow columns.
        @ViewBuilder
        private var metricsLayout: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))

            layout {
                StatCardView(label: "TIME", value: "04:18")
                StatCardView(label: "CALORIES", value: "86")
                StatCardView(label: "RATE(AVG)", value: "147/min", valueColor: AppColors.accent)
            }
        }
    }

    /// Demonstrates clearer month navigation and a less fragmented session row.
    private struct SuggestedHistoryPreview: View {
        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 18) {
                        monthNavigation
                        monthlySummary
                        sessionSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                .navigationTitle("History")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Records", systemImage: "trophy.fill", action: {})
                    }
                }
            }
        }

        private var monthNavigation: some View {
            HStack(spacing: 12) {
                Button(action: {}) {
                    Image(systemName: "chevron.left")
                        .frame(width: 36, height: 36)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)

                VStack(spacing: 3) {
                    Text("June 2026")
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)
                    Button("Today", action: {})
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.accent)
                }
                .frame(maxWidth: .infinity)

                Button(action: {}) {
                    Image(systemName: "chevron.right")
                        .frame(width: 36, height: 36)
                }
                .appGlassButton()
                .buttonBorderShape(.circle)
            }
            .padding(16)
            .background(AppColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private var monthlySummary: some View {
            HStack(spacing: 10) {
                StatCardView(label: "SESSIONS", value: "7", valueColor: AppColors.accent)
                StatCardView(label: "JUMPS", value: "6.8K")
                StatCardView(label: "TIME", value: "38m")
            }
        }

        private var sessionSection: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("SESSIONS THIS MONTH")
                    .font(AppFonts.badgeLabel)
                    .tracking(2)
                    .foregroundStyle(AppColors.textMuted)

                suggestedSessionRow(date: "Jun 14, 7:32 PM", jumps: "847", duration: "05:12", calories: "156 kcal")
                suggestedSessionRow(date: "Jun 11, 6:48 AM", jumps: "1,024", duration: "07:04", calories: "198 kcal")
            }
        }

        /// A two-column metadata grid stays aligned when localized labels or values
        /// grow, avoiding the visual breaks caused by several independent chips.
        private func suggestedSessionRow(
            date: String,
            jumps: String,
            duration: String,
            calories: String
        ) -> some View {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(date)
                        .font(AppFonts.bodyLabelStrong)
                        .foregroundStyle(AppColors.textPrimary)

                    Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 7) {
                        GridRow {
                            metric(systemImage: "figure.jumprope", value: jumps, label: "Jumps")
                            metric(systemImage: "timer", value: duration, label: "Duration")
                        }
                        GridRow {
                            metric(systemImage: "flame.fill", value: calories, label: "Calories")
                            Color.clear.frame(height: 1)
                        }
                    }
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.tabInactive)
            }
            .padding(16)
            .background(AppColors.cardSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }

        private func metric(systemImage: String, value: String, label: LocalizedStringKey) -> some View {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(label)
                        .font(AppFonts.eyebrowLabel)
                        .foregroundStyle(AppColors.textMuted)
                    Text(value)
                        .font(AppFonts.smallValueMonospaced)
                        .foregroundStyle(AppColors.textPrimary)
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(AppColors.accent)
            }
        }
    }

    /// Demonstrates a completion screen that foregrounds the main result and places
    /// specialist analytics in a disclosure group rather than one uninterrupted list.
    private struct SuggestedCompletionPreview: View {
        @State private var showsDetails: Bool

        /// Allows Canvas to display both the concise default and the expanded
        /// analytics state without requiring manual interaction for every comparison.
        init(showsDetails: Bool = false) {
            _showsDetails = State(initialValue: showsDetails)
        }

        var body: some View {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(AppFonts.system(56, weight: .semibold))
                            .foregroundStyle(AppColors.accent)
                        Text("Session Complete!")
                            .font(AppFonts.screenTitle)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("1,248 jumps in 08:00")
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    HStack(spacing: 10) {
                        SessionMetricCard(label: "JUMPS", value: "1,248", valueColor: AppColors.accent)
                        SessionMetricCard(label: "AVG RATE", value: "156/min")
                    }

                    AICommentCardView(
                        comment: "Strong control through the middle section, with a consistent finish and only one long break.",
                        isLoading: false
                    )

                    DisclosureGroup(isExpanded: $showsDetails) {
                        VStack(spacing: 8) {
                            detailRow("Peak Rate", value: "176/min")
                            detailRow("Rhythm Consistency", value: "92%")
                            detailRow("Longest Streak", value: "286 jumps")
                            detailRow("Calories Per Minute", value: "26.8 kcal/min")
                        }
                        .padding(.top, 12)
                    } label: {
                        Label("Detailed Analytics", systemImage: "chart.xyaxis.line")
                            .font(AppFonts.cardTitle)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    .tint(AppColors.accent)
                    .padding(16)
                    .background(AppColors.cardSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
            .safeAreaInset(edge: .bottom) {
                Button(action: {}) {
                    Label("DONE", systemImage: "checkmark")
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .appGlassButton(prominent: true, tint: AppColors.accent)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(AppColors.bgPrimary.opacity(0.96))
            }
        }

        private func detailRow(_ label: LocalizedStringKey, value: String) -> some View {
            HStack {
                Text(label)
                    .font(AppFonts.secondaryActionLabel)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text(value)
                    .font(AppFonts.metricDetailMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .padding(.vertical, 8)
        }
    }

    #Preview("Suggestion - Home") {
        SuggestedPreviewCanvas {
            SuggestedHomePreview()
        }
    }

    #Preview("Suggestion - Active Session") {
        SuggestedPreviewCanvas {
            SuggestedActiveSessionPreview()
        }
    }

    #Preview("Suggestion - Active Accessibility") {
        SuggestedPreviewCanvas {
            SuggestedActiveSessionPreview()
                .environment(\.dynamicTypeSize, .accessibility2)
        }
    }

    #Preview("Suggestion - History") {
        SuggestedPreviewCanvas {
            SuggestedHistoryPreview()
        }
    }

    #Preview("Suggestion - Completion Summary") {
        SuggestedPreviewCanvas {
            SuggestedCompletionPreview()
        }
    }

    #Preview("Suggestion - Completion Expanded") {
        SuggestedPreviewCanvas {
            SuggestedCompletionPreview(showsDetails: true)
        }
    }
#endif
