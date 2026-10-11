//
//  PurchaseManager.swift
//  JumpRec
//
//  Created by kinn on 2026/09/20.
//

import Foundation
import Observation
import StoreKit

/// Verifies StoreKit purchases and syncs unlimited-workout entitlements.
@MainActor
@Observable
public final class PurchaseManager: Sendable {
    // MARK: - Constants

    /// The App Store product identifier for unlocking unlimited workout tracking.
    public static let unlimitedWorkoutsProductID = "com.kinn.JumpRec.unlimitedWorkouts"

    /// Shared singleton instance accessible across the app.
    public static let shared = PurchaseManager()

    // MARK: - Observable State

    /// Indicates whether the user has an active entitlement for unlimited workouts.
    public private(set) var hasUnlockedUnlimitedWorkouts: Bool = false

    /// The StoreKit Product loaded from the App Store.
    public private(set) var product: Product? = nil

    /// Indicates whether a purchase transaction is actively processing.
    public private(set) var isPurchasing: Bool = false

    /// Indicates whether a restore transaction request is actively running.
    public private(set) var isRestoring: Bool = false

    /// The most recent user-facing error message, or nil if the last operation succeeded.
    public private(set) var errorMessage: String? = nil

    // MARK: - Private State

    /// Background task listening for out-of-band StoreKit transaction updates (e.g. Ask to Buy, Family Sharing).
    @ObservationIgnored
    private var updatesTask: Task<Void, Never>? = nil

    /// Key-value store used to mirror entitlement status to watchOS and other devices.
    @ObservationIgnored
    private let store = NSUbiquitousKeyValueStore.default

    // MARK: - Initialization

    private init() {
        // Prime cached state from ubiquitous key-value store first for immediate UI rendering
        hasUnlockedUnlimitedWorkouts = store.bool(forKey: "hasUnlockedUnlimitedWorkouts")
        startListeningForTransactionUpdates()

        Task {
            await loadProduct()
            await updatePurchasedState()
        }
    }

    deinit {
        updatesTask?.cancel()
    }

    // MARK: - Transaction Listener

    /// Observes external transactions, including approvals, Family Sharing, and other devices.
    private func startListeningForTransactionUpdates() {
        updatesTask = Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                await handle(transactionVerification: result)
            }
        }
    }

    // MARK: - Product Loading

    /// Loads the StoreKit product metadata and price from Apple's App Store servers.
    public func loadProduct() async {
        do {
            let products = try await Product.products(for: [Self.unlimitedWorkoutsProductID])
            product = products.first(where: { $0.id == Self.unlimitedWorkoutsProductID })
        } catch {
            print("[PurchaseManager] Failed to load StoreKit product: \(error.localizedDescription)")
            // Non-fatal error; UI gracefully falls back to a placeholder or retries on demand
        }
    }

    // MARK: - Entitlement Verification

    /// Syncs the unlimited license from verified, unrevoked StoreKit entitlements.
    public func updatePurchasedState() async {
        var isUnlocked = false

        for await result in Transaction.currentEntitlements {
            guard case let .verified(transaction) = result else {
                continue
            }

            if transaction.productID == Self.unlimitedWorkoutsProductID {
                // If revocationDate is nil, the transaction is valid and active.
                if transaction.revocationDate == nil {
                    isUnlocked = true
                    break
                }
            }
        }

        applyEntitlementState(isUnlocked)
    }

    /// Handles a verified or unverified transaction update delivered from StoreKit.
    private func handle(transactionVerification result: VerificationResult<Transaction>) async {
        guard case let .verified(transaction) = result else {
            print("[PurchaseManager] Received unverified transaction update; skipping.")
            return
        }

        if transaction.productID == Self.unlimitedWorkoutsProductID {
            let isUnlocked = transaction.revocationDate == nil
            applyEntitlementState(isUnlocked)
        }

        // Always finish the transaction to inform StoreKit that delivery was completed.
        await transaction.finish()
    }

    /// Persists entitlement state locally, in iCloud key-value storage, and notifies observers.
    private func applyEntitlementState(_ isUnlocked: Bool) {
        hasUnlockedUnlimitedWorkouts = isUnlocked
        store.set(isUnlocked, forKey: "hasUnlockedUnlimitedWorkouts")
        store.synchronize()
        NotificationCenter.default.post(name: .jumpRecSettingsDidUpdate, object: nil)
    }

    // MARK: - Purchase Flow

    /// Purchases the unlimited license; returns true only for a verified purchase.
    @discardableResult
    public func purchase() async -> Bool {
        guard let product else {
            // Attempt to reload the product if it was not ready yet
            await loadProduct()
            guard let product = self.product else {
                errorMessage = String(localized: "Product details could not be loaded from the App Store. Please check your internet connection.")
                return false
            }
            return await executePurchase(for: product)
        }

        return await executePurchase(for: product)
    }

    private func executePurchase(for product: Product) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()

            switch result {
            case let .success(verification):
                switch verification {
                case let .unverified(_, verificationError):
                    print("[PurchaseManager] Transaction verification failed: \(verificationError.localizedDescription)")
                    errorMessage = String(localized: "Purchase verification failed. Please try again.")
                    return false

                case let .verified(transaction):
                    applyEntitlementState(true)
                    await transaction.finish()
                    return true
                }

            case .userCancelled:
                // User intentionally dismissed the Apple Pay sheet; no error needed.
                return false

            case .pending:
                // Ask to Buy or family approval required; entitlement will arrive via Transaction.updates
                errorMessage = String(localized: "Purchase is pending approval.")
                return false

            @unknown default:
                return false
            }
        } catch {
            print("[PurchaseManager] Purchase failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Restore Flow

    /// Restores purchases and refreshes entitlements from the App Store.
    public func restorePurchases() async {
        isRestoring = true
        errorMessage = nil
        defer { isRestoring = false }

        do {
            // Sync may request authentication and updates current entitlements.
            try await AppStore.sync()
            await updatePurchasedState()
        } catch {
            print("[PurchaseManager] Restore purchases failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}
