//
//  SettingsView.swift
//  JumpRec
//

import SwiftUI
import UIKit

/// Presents user-editable workout settings before a session starts.
struct SettingsView: View {
    /// The persisted settings being edited by the sheet.
    @Bindable var settings: JumpRecSettings
    /// Dismisses the sheet after changes are applied.
    @Environment(\.dismiss) private var dismiss
    @Environment(MyDataStore.self) private var dataStore
    @State private var purchaseManager = PurchaseManager.shared

    // MARK: - View State

    /// Controls presentation of the paywall sheet.
    @State private var showPaywall = false
    /// Controls presentation of restore feedback alerts.
    @State private var isShowingRestoreAlert = false
    /// Feedback message displayed in restore alert.
    @State private var restoreAlertMessage = ""

    /// Tracks the selected goal type while editing so the user can cancel by closing the sheet.
    @State private var selectedType: GoalType = .count
    /// Tracks the editable jump-count goal value.
    @State private var countValue: Int64 = DefaultJumpCount
    /// Tracks the editable time goal value in minutes.
    @State private var timeValue: Int64 = DefaultJumpTime
    /// Controls local popover presentation for detector sensitivity explanation.
    @State private var isShowingSensitivityExplanation = false
    /// Reveals the sheet controls in the same order that the user reads and interacts with them.
    @State private var hasContentAppeared = false

    // MARK: - View

    /// Renders settings sections and the confirmation button.
    var body: some View {
        VStack(spacing: 20) {
            Text("Settings")
                .font(AppFonts.primaryButtonLabel)
                .foregroundStyle(AppColors.textPrimary)
                .staggeredAppearance(isVisible: hasContentAppeared, index: 0)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    membershipSection
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 1)

                    goalSettingsSection
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 2)

                    jumpDetectionSection
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 3)

                    audioSettingsSection
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 4)

                    iPhoneSessionSection
                        .staggeredAppearance(isVisible: hasContentAppeared, index: 5)
                }
                .padding(.bottom, 8)
            }
            .safeAreaInset(edge: .bottom) {
                // Floating confirmation button pinned to bottom edge, matching SessionCompleteView floating layout.
                Button {
                    applyGoal()
                    dismiss()
                } label: {
                    Text("Confirm")
                        .font(AppFonts.primaryButtonLabel)
                        .foregroundStyle(AppColors.bgPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                }
                .appGlassButton(prominent: true, tint: AppColors.accent)
                .staggeredAppearance(isVisible: hasContentAppeared, index: 6)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.cardSurface)
        .sheet(isPresented: $showPaywall) {
            PaywallView()
        }
        .alert(
            String(localized: "Restore Purchases"),
            isPresented: $isShowingRestoreAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
        }
        .onAppear {
            configureSegmentedControlAppearance()
            selectedType = settings.goalType
            countValue = settings.jumpCount
            timeValue = settings.jumpTime
        }
        .task {
            // Defer the reveal until the persisted values have populated the editing controls.
            await Task.yield()
            hasContentAppeared = true
        }
        .padding(.top, 20)
    }

    // MARK: - Sections

    /// Displays the one-time license unlock status and free workout quota progress.
    private var membershipSection: some View {
        settingsSection(title: String(localized: "Membership & Quota")) {
            if purchaseManager.hasUnlockedUnlimitedWorkouts {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(AppFonts.system(22))
                        .foregroundStyle(AppColors.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Unlimited Workouts Active")
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textPrimary)

                        Text("You have unlocked lifetime unlimited workout tracking.")
                            .font(AppFonts.bodySmall)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                }
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Free Workouts")
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        Text("\(dataStore.qualifiedSessionsCount()) / \(JumpRecSettings.freeWorkoutQuota)")
                            .font(AppFonts.bodyLabelStrong)
                            .foregroundStyle(dataStore.qualifiedSessionsCount() >= JumpRecSettings.freeWorkoutQuota ? AppColors.danger : AppColors.accent)
                    }

                    ProgressView(
                        value: min(Double(dataStore.qualifiedSessionsCount()), Double(JumpRecSettings.freeWorkoutQuota)),
                        total: Double(JumpRecSettings.freeWorkoutQuota)
                    )
                    .tint(dataStore.qualifiedSessionsCount() >= JumpRecSettings.freeWorkoutQuota ? AppColors.danger : AppColors.accent)

                    Text("Includes sessions with 100+ jumps. When you complete 100 workouts, unlock lifetime unlimited tracking with a single purchase.")
                        .font(AppFonts.bodySmall)
                        .foregroundStyle(AppColors.textSecondary)

                    HStack(spacing: 12) {
                        Button {
                            showPaywall = true
                        } label: {
                            Text("Unlock Unlimited")
                                .font(AppFonts.primaryButtonLabel)
                                .foregroundStyle(AppColors.bgPrimary)
                                .frame(maxWidth: .infinity)
                                .frame(height: 44)
                        }
                        .appGlassButton(prominent: true, tint: AppColors.accent)

                        Button {
                            Task {
                                await purchaseManager.restorePurchases()
                                if purchaseManager.hasUnlockedUnlimitedWorkouts {
                                    restoreAlertMessage = String(localized: "Your previous purchase was successfully restored!")
                                    isShowingRestoreAlert = true
                                } else if purchaseManager.errorMessage != nil {
                                    restoreAlertMessage = purchaseManager.errorMessage ?? String(localized: "Could not restore purchases.")
                                    isShowingRestoreAlert = true
                                } else {
                                    restoreAlertMessage = String(localized: "No previous purchase was found for this Apple ID.")
                                    isShowingRestoreAlert = true
                                }
                            }
                        } label: {
                            Text("Restore")
                                .font(AppFonts.secondaryActionLabel)
                                .foregroundStyle(AppColors.textSecondary)
                                .frame(height: 44)
                                .padding(.horizontal, 12)
                        }
                        .appGlassButton(tint: AppColors.textMuted)
                    }
                }
            }
        }
    }

    /// Groups goal controls so this sheet can grow into a broader settings surface without mixing concerns.
    private var goalSettingsSection: some View {
        settingsSection(title: String(localized: "Goal Settings")) {
            segmentedControl

            stepperRow
                .animation(.easeInOut, value: selectedType)
        }
    }

    /// Lets the user opt into staying on the iPhone route when compatible headphones can provide motion data.
    private var iPhoneSessionSection: some View {
        settingsSection(title: String(localized: "iPhone Session")) {
            settingsToggle(
                isOn: $settings.preferHeadphonesForIPhoneSessions,
                title: String(localized: "Prefer Headphones for iPhone Sessions"),
                description: String(localized: "When compatible headphones are available, start on iPhone instead of Apple Watch.")
            )
        }
    }

    /// Lets the user tune jump counting sensitivity without exposing raw acceleration thresholds.
    private var jumpDetectionSection: some View {
        settingsSection(title: String(localized: "Jump Detection")) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Button {
                        isShowingSensitivityExplanation = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(String(localized: "Detection Sensitivity"))
                                .font(AppFonts.cardTitle)
                                .foregroundStyle(AppColors.textPrimary)

                            Image(systemName: "info.circle.fill")
                                .font(AppFonts.smallValue)
                                .foregroundStyle(AppColors.textMuted)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text(String(localized: "Shows an explanation for detection sensitivity.")))
                    .popover(isPresented: $isShowingSensitivityExplanation) {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(String(localized: "If there are false detections, try lowering the sensitivity."))
                                .font(AppFonts.bodySmall)
                                .fixedSize(horizontal: false, vertical: true)

                            Text(String(localized: "If jumps are not detected, try increasing the sensitivity."))
                                .font(AppFonts.bodySmall)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)
                        .frame(maxWidth: 400, alignment: .leading)
                        .presentationCompactAdaptation(.popover)
                    }

                    Spacer(minLength: 12)

                    Text(thresholdAdjustmentDisplayValue)
                        .font(AppFonts.detailValue)
                        .foregroundStyle(AppColors.accent)
                        .contentTransition(.numericText())
                        .animation(.bouncy, value: thresholdAdjustmentDisplayValue)
                        .accessibilityHidden(true)
                }

                Slider(
                    value: sensitivitySliderBinding,
                    in: MinimumJumpDetectorThresholdAdjustmentPercentage ... MaximumJumpDetectorThresholdAdjustmentPercentage,
                    step: 5
                )
                .tint(AppColors.accent)
                .accessibilityLabel(Text(String(localized: "Detection sensitivity")))
                .accessibilityValue(Text(thresholdAdjustmentAccessibilityValue))
                .accessibilityHint(Text(String(localized: "Adjusts jump detection sensitivity.")))
            }
        }
    }

    /// Groups spoken-feedback controls so users can mute progress cues without changing haptics or goal completion.
    private var audioSettingsSection: some View {
        settingsSection(title: String(localized: "Audio Settings")) {
            settingsToggle(
                isOn: $settings.shouldSpeakJumpCountAnnouncements,
                title: String(localized: "Speak Jump Count"),
                description: String(localized: "Play speech and haptics for every 100-jump milestone.")
            )

            Divider()
                .overlay(AppColors.accent.opacity(0.16))

            settingsToggle(
                isOn: $settings.shouldSpeakJumpTimeAnnouncements,
                title: String(localized: "Speak Jump Time"),
                description: String(localized: "Play speech and haptics for each elapsed minute.")
            )
        }
    }

    /// Applies the app's section chrome consistently without forcing callers into a separate reusable type.
    private func settingsSection(title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(AppFonts.badgeLabel)
                .tracking(2)
                .foregroundStyle(AppColors.textMuted)

            VStack(spacing: 18) {
                content()
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.bgPrimary.opacity(0.35))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .stroke(AppColors.accent.opacity(0.18), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }

    /// Renders a settings row with a switch toggle and an info mark icon that shows explanatory copy in a popover when tapped.
    private func settingsToggle(isOn: Binding<Bool>, title: String, description: String) -> some View {
        SettingsToggleRow(isOn: isOn, title: title, description: description)
    }

    // MARK: - Segmented Control

    /// Switches between count and time goal editing.
    private var segmentedControl: some View {
        Picker("Goal Type", selection: $selectedType) {
            Text("Jump Count")
                .tag(GoalType.count)
            Text("Jump Time")
                .tag(GoalType.time)
        }
        .pickerStyle(.segmented)
        .controlSize(.large)
    }

    // MARK: - Stepper Row

    /// Displays the stepper controls for the active goal type.
    private var stepperRow: some View {
        HStack(spacing: 32) {
            Button {
                adjustValue(by: -stepAmount)
            } label: {
                Image(systemName: "minus")
                    .font(AppFonts.largeControlIcon)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
            }
            .appGlassButton(tint: AppColors.accent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(decrementButtonAccessibilityLabel)
            .accessibilityHint(stepperAccessibilityHint)

            VStack(spacing: 4) {
                Text(displayValue)
                    .font(AppFonts.metricValueXLMonospaced)
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())

                Text(unitLabel)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .frame(minWidth: 100)

            Button {
                adjustValue(by: stepAmount)
            } label: {
                Image(systemName: "plus")
                    .font(AppFonts.largeControlIcon)
                    .foregroundStyle(AppColors.accent)
                    .frame(width: 48, height: 48)
            }
            .appGlassButton(tint: AppColors.accent)
            .buttonBorderShape(.circle)
            .accessibilityLabel(incrementButtonAccessibilityLabel)
            .accessibilityHint(stepperAccessibilityHint)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(goalValueAccessibilityLabel)
        .accessibilityValue(goalValueAccessibilityValue)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjustValue(by: stepAmount)
            case .decrement:
                adjustValue(by: -stepAmount)
            @unknown default:
                break
            }
        }
    }

    // MARK: - Helpers

    /// Binds the UI slider to the stored threshold adjustment percentage, inverting the sign
    /// so that moving the slider to the right increases sensitivity (lower acceleration threshold).
    private var sensitivitySliderBinding: Binding<Double> {
        Binding(
            get: { -settings.jumpDetectorThresholdAdjustmentPercentage },
            set: { settings.jumpDetectorThresholdAdjustmentPercentage = -$0 }
        )
    }

    /// Formats the detector sensitivity tier for display in the settings section.
    ///
    /// Maps internal percentage offsets (-50% to +50%) to human-readable sensitivity levels:
    /// - Negative percentages lower acceleration threshold -> Higher sensitivity
    /// - Positive percentages raise acceleration threshold -> Lower sensitivity
    /// - Zero percentage represents standard default sensitivity
    private var thresholdAdjustmentDisplayValue: String {
        let roundedPercentage = Int(settings.jumpDetectorThresholdAdjustmentPercentage.rounded())
        switch roundedPercentage {
        case ..<(-20):
            return String(localized: "High")
        case -20 ... -5:
            return String(localized: "Slightly High")
        case 5 ... 20:
            return String(localized: "Slightly Low")
        case 21...:
            return String(localized: "Low")
        default:
            return String(localized: "Standard")
        }
    }

    /// Formats the current sensitivity tier for assistive technologies.
    private var thresholdAdjustmentAccessibilityValue: String {
        thresholdAdjustmentDisplayValue
    }

    /// Returns the value currently shown in the editor.
    private var displayValue: String {
        if selectedType == .count {
            countValue.formatted()
        } else {
            "\(timeValue)"
        }
    }

    /// Returns the unit label for the currently selected goal type.
    private var unitLabel: String {
        if selectedType == .time, timeValue == 1 {
            return String(localized: "minute")
        }
        return selectedType == .count ? String(localized: "jumps") : String(localized: "minutes")
    }

    /// Returns the step size used when adjusting the current goal.
    private var stepAmount: Int64 {
        selectedType == .count ? 100 : 1
    }

    /// Names the editable goal value for VoiceOver adjustable gestures.
    private var goalValueAccessibilityLabel: String {
        selectedType == .count ? String(localized: "Jump count goal") : String(localized: "Jump time goal")
    }

    /// Formats the current staged value with its unit so VoiceOver announces the full setting.
    private var goalValueAccessibilityValue: String {
        if selectedType == .count {
            return String(
                format: String(localized: "%@ jumps"),
                countValue.formatted()
            )
        }
        return String(
            format: String(localized: "%lld minutes"),
            timeValue
        )
    }

    /// Explains that the circular buttons and adjustable gesture change the staged goal before confirmation.
    private var stepperAccessibilityHint: Text {
        Text("Adjusts the goal value before you confirm settings.")
    }

    /// Names the decrement button with the same unit the visible control is editing.
    private var decrementButtonAccessibilityLabel: Text {
        Text(selectedType == .count ? "Decrease jump count goal" : "Decrease jump time goal")
    }

    /// Names the increment button with the same unit the visible control is editing.
    private var incrementButtonAccessibilityLabel: Text {
        Text(selectedType == .count ? "Increase jump count goal" : "Increase jump time goal")
    }

    /// Increments or decrements the active goal value while respecting minimums.
    private func adjustValue(by amount: Int64) {
        withAnimation {
            if selectedType == .count {
                countValue = max(100, countValue + amount)
            } else {
                timeValue = max(1, timeValue + amount)
            }
        }
    }

    /// Writes the edited goal values back to persisted settings.
    private func applyGoal() {
        if selectedType == .count {
            settings.jumpCount = countValue
        } else {
            settings.jumpTime = timeValue
        }
        settings.goalType = selectedType
    }

    /// Applies the custom UIKit appearance used by the segmented control.
    private func configureSegmentedControlAppearance() {
        let selectedTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.bgPrimary),
            .font: AppFonts.segmentedControlLabel,
        ]
        let normalTextAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: UIColor(AppColors.textSecondary),
            .font: AppFonts.segmentedControlLabel,
        ]

        UISegmentedControl.appearance().selectedSegmentTintColor = UIColor(AppColors.accent)
        UISegmentedControl.appearance().setTitleTextAttributes(normalTextAttributes, for: .normal)
        UISegmentedControl.appearance().setTitleTextAttributes(selectedTextAttributes, for: .selected)
    }
}

// MARK: - Settings Subviews

/// Renders a toggle setting row with an info mark icon that reveals explanatory copy inside a popover.
private struct SettingsToggleRow: View {
    /// Binding controlling the toggle state.
    @Binding var isOn: Bool
    /// Title text displayed next to the info icon.
    let title: String
    /// Detailed description shown in the popover when the info icon is tapped.
    let description: String

    /// Controls local popover presentation for the setting description.
    @State private var isShowingExplanation = false

    var body: some View {
        Toggle(isOn: $isOn) {
            Button {
                isShowingExplanation = true
            } label: {
                HStack(spacing: 6) {
                    Text(title)
                        .font(AppFonts.cardTitle)
                        .foregroundStyle(AppColors.textPrimary)

                    Image(systemName: "info.circle.fill")
                        .font(AppFonts.smallValue)
                        .foregroundStyle(AppColors.textMuted)
                }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text(description))
            .popover(isPresented: $isShowingExplanation) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(description)
                        .font(AppFonts.bodySmall)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)
                .frame(maxWidth: 280, alignment: .leading)
                .presentationCompactAdaptation(.popover)
            }
        }
        .toggleStyle(.switch)
        .tint(AppColors.accent)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(description))
    }
}

#Preview {
    SettingsView(settings: JumpRecSettings())
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
}
