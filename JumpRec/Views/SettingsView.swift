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

    // MARK: - View State

    /// Tracks the selected goal type while editing so the user can cancel by closing the sheet.
    @State private var selectedType: GoalType = .count
    /// Tracks the editable jump-count goal value.
    @State private var countValue: Int64 = DefaultJumpCount
    /// Tracks the editable time goal value in minutes.
    @State private var timeValue: Int64 = DefaultJumpTime
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

            VStack(spacing: 16) {
                goalSettingsSection
                    .staggeredAppearance(isVisible: hasContentAppeared, index: 1)

                iPhoneSessionSection
                    .staggeredAppearance(isVisible: hasContentAppeared, index: 2)

                audioSettingsSection
                    .staggeredAppearance(isVisible: hasContentAppeared, index: 3)
            }

            Spacer()

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
            .staggeredAppearance(isVisible: hasContentAppeared, index: 4)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.cardSurface)
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

    /// Renders a settings row with a switch and explanatory copy.
    ///
    /// Keeping this as a helper avoids duplicating the typography and wrapping rules
    /// across sections while still leaving each setting label close to its binding.
    private func settingsToggle(isOn: Binding<Bool>, title: String, description: String) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(description)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.switch)
        .tint(AppColors.accent)
        .accessibilityLabel(Text(title))
        .accessibilityHint(Text(description))
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

#Preview {
    SettingsView(settings: JumpRecSettings())
        .presentationDetents([.large])
        .preferredColorScheme(.dark)
}
