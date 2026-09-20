//
//  PaywallView.swift
//  JumpRec
//
//  Created by Codex on 2026/09/20.
//

import StoreKit
import SwiftUI

/// Presents the paywall modal sheet when the user reaches the 100-workout free quota.
///
/// JumpRec's freemium model allows 100 workouts with at least 100 jumps for free.
/// When the quota is exhausted, users purchase a one-time lifetime license to start new sessions.
/// Even if users choose not to purchase, their workout history, personal records, and statistics
/// remain accessible at all times in compliance with Apple App Store Review Guidelines.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MyDataStore.self) private var dataStore
    @State private var purchaseManager = PurchaseManager.shared
    @State private var isShowingRestoreAlert = false
    @State private var restoreAlertMessage = ""

    /// Number of completed sessions with >= 100 jumps.
    private var qualifiedCount: Int {
        dataStore.qualifiedSessionsCount()
    }

    /// Indicates whether the 100 free workouts quota has actually been exhausted.
    private var isQuotaReached: Bool {
        qualifiedCount >= JumpRecSettings.freeWorkoutQuota
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppColors.bgPrimary.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        headerSection

                        featuresSection

                        pricingAndActionSection

                        footerSection
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(AppFonts.system(20))
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .accessibilityLabel(Text("Close"))
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .presentationBackground(AppColors.cardSurface)
        .alert(
            String(localized: "Restore Purchases"),
            isPresented: $isShowingRestoreAlert
        ) {
            Button(String(localized: "OK"), role: .cancel) {}
        } message: {
            Text(restoreAlertMessage)
        }
        .onChange(of: purchaseManager.hasUnlockedUnlimitedWorkouts) { _, isUnlocked in
            if isUnlocked {
                dismiss()
            }
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(AppColors.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: isQuotaReached ? "trophy.fill" : "figure.jumprope")
                    .font(AppFonts.system(38, weight: .bold))
                    .foregroundStyle(AppColors.accent)
            }
            .padding(.top, 8)

            Text(headerTitle)
                .font(AppFonts.screenTitle)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            Text(headerSubtitle)
                .font(AppFonts.bodyRegular)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 8)
        }
    }

    /// Dynamic title: celebrates milestone if quota reached, or general unlock title if opened earlier from settings.
    private var headerTitle: String {
        if isQuotaReached {
            String(localized: "100 Workouts Milestone! 🎉")
        } else {
            String(localized: "Unlock Unlimited Workouts")
        }
    }

    /// Dynamic subtitle: specifies current session count when under quota.
    private var headerSubtitle: String {
        if isQuotaReached {
            String(localized: "You've logged 100 great sessions with JumpRec. Unlock unlimited workout tracking forever with a single, one-time purchase.")
        } else {
            String(
                format: String(localized: "You've logged %lld of %lld free workouts. Unlock unlimited workout tracking anytime with a single, one-time purchase."),
                Int64(qualifiedCount),
                Int64(JumpRecSettings.freeWorkoutQuota)
            )
        }
    }

    // MARK: - Features Section

    private var featuresSection: some View {
        VStack(spacing: 12) {
            featureRow(
                icon: "infinity",
                title: String(localized: "Unlimited Workouts"),
                description: String(localized: "Start and track unlimited jump rope sessions without any future limits.")
            )

            featureRow(
                icon: "cart.badge.questionmark",
                title: String(localized: "One-Time Purchase"),
                description: String(localized: "No subscriptions and no recurring fees. Pay once and keep forever.")
            )

            featureRow(
                icon: "person.2.fill",
                title: String(localized: "Family Sharing"),
                description: String(localized: "Share unlimited access across your family members via iCloud.")
            )

            featureRow(
                icon: "chart.bar.fill",
                title: String(localized: "Your Data is Always Yours"),
                description: String(localized: "All past workout history, personal records, and stats remain fully readable.")
            )
        }
        .padding(16)
        .background(AppColors.cardSurface.opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(AppColors.accent.opacity(0.15), lineWidth: 1)
        )
    }

    private func featureRow(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(AppFonts.system(18, weight: .semibold))
                .foregroundStyle(AppColors.accent)
                .frame(width: 24, height: 24)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFonts.cardTitle)
                    .foregroundStyle(AppColors.textPrimary)

                Text(description)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
        }
    }

    // MARK: - Pricing and Action Section

    private var pricingAndActionSection: some View {
        VStack(spacing: 12) {
            if let errorMessage = purchaseManager.errorMessage {
                Text(errorMessage)
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.danger)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            Button {
                Task {
                    let success = await purchaseManager.purchase()
                    if success {
                        dismiss()
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    if purchaseManager.isPurchasing {
                        ProgressView()
                            .tint(AppColors.bgPrimary)
                    } else {
                        Text("Unlock Unlimited Workouts")
                            .font(AppFonts.primaryButtonLabel)
                            .foregroundStyle(AppColors.bgPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 56)
            }
            .appGlassButton(prominent: true, tint: AppColors.accent)
            .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)

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
                if purchaseManager.isRestoring {
                    ProgressView()
                        .tint(AppColors.accent)
                        .frame(height: 32)
                } else {
                    Text("Restore Purchases")
                        .font(AppFonts.secondaryActionLabel)
                        .foregroundStyle(AppColors.textSecondary)
                        .underline()
                }
            }
            .disabled(purchaseManager.isPurchasing || purchaseManager.isRestoring)
            .padding(.top, 4)
        }
    }

    // MARK: - Footer Section

    private var footerSection: some View {
        VStack(spacing: 6) {
            Text("One-time payment charged to your Apple ID account. Family Sharing supported.")
                .font(AppFonts.system(11))
                .foregroundStyle(AppColors.textMuted)
                .multilineTextAlignment(.center)

            Button {
                dismiss()
            } label: {
                Text("Continue reviewing past workouts")
                    .font(AppFonts.bodySmall)
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.top, 4)
        }
    }
}

#Preview {
    PaywallView()
        .environment(MyDataStore.shared)
}
