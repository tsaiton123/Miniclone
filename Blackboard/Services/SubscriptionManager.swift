//
//  SubscriptionManager.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/03.
//

import Foundation
import StoreKit
import Combine

/// Manages subscription purchases and entitlements using StoreKit 2
@MainActor
class SubscriptionManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Available subscription products from the App Store
    @Published private(set) var products: [Product] = []
    
    /// Current subscription status
    @Published private(set) var subscriptionStatus: SubscriptionStatus = .notSubscribed
    
    /// Current active subscription tier
    @Published private(set) var currentTier: SubscriptionTier = .free
    
    /// Loading state for products
    @Published private(set) var isLoading: Bool = false
    
    /// Error message if any operation fails
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    private var updateListenerTask: Task<Void, Error>?
    
    /// Tracks a pending upgrade that hasn't been reflected in entitlements yet
    /// This prevents downgrades when entitlements are stale
    private var pendingUpgradeTier: SubscriptionTier?
    
    // MARK: - Initialization
    
    init() {
        // Start listening for transaction updates
        updateListenerTask = listenForTransactionUpdates()
        
        // Load products and check existing entitlements
        Task {
            await loadProducts()
            await updateSubscriptionStatus()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - Public Methods
    
    /// Load available subscription products from the App Store
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let storeProducts = try await Product.products(for: SubscriptionProductIDs.all)
            
            // Sort by price (basic first, then pro)
            products = storeProducts.sorted { $0.price < $1.price }
            
            print("[SubscriptionManager] Loaded \(products.count) products")
        } catch {
            print("[SubscriptionManager] Failed to load products: \(error)")
            errorMessage = "Failed to load subscription options. Please try again."
        }
    }
    
    /// Purchase a subscription product
    func purchase(_ product: Product) async -> Bool {
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                // Check if the transaction is verified
                let transaction = try checkVerified(verification)
                
                // IMPORTANT: Use product.id (what user is purchasing), NOT transaction.productID
                // In subscription group upgrades, transaction.productID may return the OLD subscription
                // while the upgrade is being processed. product.id is always the intent.
                if let purchasedTier = SubscriptionTier(rawValue: product.id) {
                    print("[SubscriptionManager] Purchase verified for tier: \(purchasedTier.displayName) (product: \(product.id))")
                    
                    // If purchased tier is higher, update immediately before waiting for entitlements sync
                    if purchasedTier > currentTier {
                        print("[SubscriptionManager] Upgrading immediately to: \(purchasedTier.displayName)")
                        
                        // Set pending upgrade to prevent any stale entitlement checks from downgrading
                        pendingUpgradeTier = purchasedTier
                        
                        objectWillChange.send()
                        currentTier = purchasedTier
                        subscriptionStatus = .subscribed(tier: purchasedTier, expirationDate: transaction.expirationDate)
                    }
                } else {
                    print("[SubscriptionManager] Warning: Could not match product.id to tier: \(product.id)")
                }
                
                // Finish the transaction first
                await transaction.finish()
                
                // Small delay to allow StoreKit to sync entitlements
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                
                // Then update subscription status from entitlements (may catch additional subscriptions)
                // Use preventDowngrade to avoid stale entitlements overwriting the immediate upgrade
                await updateSubscriptionStatus(preventDowngrade: true)
                
                print("[SubscriptionManager] Purchase successful: \(product.id)")
                return true
                
            case .userCancelled:
                print("[SubscriptionManager] User cancelled purchase")
                return false
                
            case .pending:
                print("[SubscriptionManager] Purchase pending (e.g., Ask to Buy)")
                errorMessage = "Purchase is pending approval."
                return false
                
            @unknown default:
                print("[SubscriptionManager] Unknown purchase result")
                return false
            }
        } catch {
            print("[SubscriptionManager] Purchase failed: \(error)")
            errorMessage = "Purchase failed: \(error.localizedDescription)"
            return false
        }
    }
    
    /// Restore previous purchases
    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await updateSubscriptionStatus()
            print("[SubscriptionManager] Purchases restored")
        } catch {
            print("[SubscriptionManager] Restore failed: \(error)")
            errorMessage = "Failed to restore purchases. Please try again."
        }
    }
    
    /// Check if a specific feature is available with current subscription
    func hasAccess(to feature: SubscriptionFeature) -> Bool {
        switch feature {
        case .unlimitedNotes:
            return currentTier.hasUnlimitedNotes
        case .pdfImport:
            return currentTier.hasPDFImport
        case .aiFeatures:
            return currentTier.hasAIFeatures
        }
    }
    
    /// Get the product for a specific tier
    func product(for tier: SubscriptionTier) -> Product? {
        products.first { $0.id == tier.rawValue }
    }
    
    /// Force refresh the subscription status - call this when returning to a view
    func refreshStatus() async {
        // Always respect pending upgrades to avoid stale entitlements downgrading the tier
        await updateSubscriptionStatus(respectPendingUpgrade: true)
    }
    
    // MARK: - Private Methods
    
    /// Update the current subscription status by checking entitlements
    /// - Parameter respectPendingUpgrade: If true, respect any pending upgrade that hasn't synced to entitlements yet
    private func updateSubscriptionStatus(preventDowngrade: Bool = false, respectPendingUpgrade: Bool = false) async {
        var highestTier: SubscriptionTier = .free
        var latestExpirationDate: Date?
        
        print("[SubscriptionManager] Checking current entitlements...")
        
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            print("[SubscriptionManager] Found entitlement result: \(result)")
            
            guard case .verified(let transaction) = result else {
                print("[SubscriptionManager] Skipping unverified transaction")
                continue
            }
            
            print("[SubscriptionManager] Verified transaction - Product: \(transaction.productID), Type: \(transaction.productType)")
            
            // Only process subscription transactions
            if transaction.productType == .autoRenewable {
                if let tier = SubscriptionTier(rawValue: transaction.productID) {
                    print("[SubscriptionManager] Matched tier: \(tier.displayName)")
                    if tier > highestTier {
                        highestTier = tier
                        latestExpirationDate = transaction.expirationDate
                    }
                } else {
                    print("[SubscriptionManager] Could not match product ID to tier: \(transaction.productID)")
                }
            }
        }
        
        print("[SubscriptionManager] Final tier from entitlements: \(highestTier.displayName)")
        
        // Check if we have a pending upgrade that hasn't been reflected in entitlements
        if let pending = pendingUpgradeTier {
            if highestTier >= pending {
                // Entitlements have caught up, clear the pending upgrade
                print("[SubscriptionManager] Entitlements caught up to pending upgrade (\(pending.displayName)), clearing pending flag")
                pendingUpgradeTier = nil
            } else if respectPendingUpgrade || preventDowngrade {
                // Entitlements haven't caught up yet, keep the pending tier
                print("[SubscriptionManager] Keeping pending upgrade tier: \(pending.displayName) (entitlements show: \(highestTier.displayName))")
                highestTier = pending
            }
        } else if preventDowngrade && highestTier < currentTier {
            // No pending upgrade but we're asked to prevent downgrade
            print("[SubscriptionManager] Preventing downgrade from \(currentTier.displayName) to \(highestTier.displayName) - keeping current tier")
            return
        }
        
        // Explicitly notify observers before updating
        objectWillChange.send()
        
        // Update published properties
        currentTier = highestTier
        
        if highestTier != .free {
            subscriptionStatus = .subscribed(tier: highestTier, expirationDate: latestExpirationDate)
        } else {
            subscriptionStatus = .notSubscribed
        }
        
        print("[SubscriptionManager] Updated status: \(currentTier.displayName), hasAIFeatures: \(currentTier.hasAIFeatures)")
    }
    
    /// Listen for transaction updates (renewals, refunds, etc.)
    private func listenForTransactionUpdates() -> Task<Void, Error> {
        Task.detached {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else {
                    continue
                }
                
                await self.updateSubscriptionStatus()
                await transaction.finish()
            }
        }
    }
    
    /// Verify a transaction result
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw SubscriptionError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
}

// MARK: - Supporting Types

/// Features that require subscription
enum SubscriptionFeature {
    case unlimitedNotes
    case pdfImport
    case aiFeatures
}

/// Subscription-related errors
enum SubscriptionError: LocalizedError {
    case verificationFailed
    case purchaseFailed
    case restoreFailed
    
    var errorDescription: String? {
        switch self {
        case .verificationFailed:
            return "Transaction verification failed"
        case .purchaseFailed:
            return "Purchase could not be completed"
        case .restoreFailed:
            return "Could not restore purchases"
        }
    }
}
