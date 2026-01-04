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
                
                // Update subscription status
                await updateSubscriptionStatus()
                
                // Finish the transaction
                await transaction.finish()
                
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
    
    // MARK: - Private Methods
    
    /// Update the current subscription status by checking entitlements
    private func updateSubscriptionStatus() async {
        var highestTier: SubscriptionTier = .free
        var latestExpirationDate: Date?
        
        // Check current entitlements
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else {
                continue
            }
            
            // Only process subscription transactions
            if transaction.productType == .autoRenewable {
                if let tier = SubscriptionTier(rawValue: transaction.productID) {
                    if tier > highestTier {
                        highestTier = tier
                        latestExpirationDate = transaction.expirationDate
                    }
                }
            }
        }
        
        // Update published properties
        currentTier = highestTier
        
        if highestTier != .free {
            subscriptionStatus = .subscribed(tier: highestTier, expirationDate: latestExpirationDate)
        } else {
            subscriptionStatus = .notSubscribed
        }
        
        print("[SubscriptionManager] Updated status: \(currentTier.displayName)")
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
