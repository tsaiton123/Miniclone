//
//  SubscriptionData.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/03.
//

import Foundation

/// Represents the subscription tiers available in Cognote
enum SubscriptionTier: String, CaseIterable, Comparable {
    case free = "free"
    case basic = "com.cognote.subscription.basic.v2"    // $5.99/mo
    case pro = "com.cognote.subscription.pro.v2"        // $9.99/mo
    
    // MARK: - Feature Access
    
    /// Maximum number of notes allowed for this tier
    var maxNotes: Int {
        switch self {
        case .free: return 3
        case .basic, .pro: return Int.max
        }
    }
    
    /// Whether this tier has unlimited notes
    var hasUnlimitedNotes: Bool { self != .free }
    
    /// Whether PDF import is available
    var hasPDFImport: Bool { self != .free }
    
    /// Whether AI features (Gemini) are available
    var hasAIFeatures: Bool { self == .pro }
    
    // MARK: - Display Properties
    
    var displayName: String {
        switch self {
        case .free: return "Free"
        case .basic: return "Basic"
        case .pro: return "Pro"
        }
    }
    
    var description: String {
        switch self {
        case .free: return "Basic note-taking"
        case .basic: return "Unlimited notes & PDF import"
        case .pro: return "Everything + AI features"
        }
    }
    
    // MARK: - Comparable
    
    static func < (lhs: SubscriptionTier, rhs: SubscriptionTier) -> Bool {
        let order: [SubscriptionTier] = [.free, .basic, .pro]
        guard let lhsIndex = order.firstIndex(of: lhs),
              let rhsIndex = order.firstIndex(of: rhs) else {
            return false
        }
        return lhsIndex < rhsIndex
    }
}

/// Represents the current subscription status
enum SubscriptionStatus: Equatable {
    case notSubscribed
    case subscribed(tier: SubscriptionTier, expirationDate: Date?)
    case expired(tier: SubscriptionTier)
    case inGracePeriod(tier: SubscriptionTier, expirationDate: Date?)
    case inBillingRetry(tier: SubscriptionTier)
    
    var isActive: Bool {
        switch self {
        case .subscribed, .inGracePeriod:
            return true
        case .notSubscribed, .expired, .inBillingRetry:
            return false
        }
    }
    
    var currentTier: SubscriptionTier {
        switch self {
        case .notSubscribed:
            return .free
        case .subscribed(let tier, _),
             .expired(let tier),
             .inGracePeriod(let tier, _),
             .inBillingRetry(let tier):
            return tier.rawValue.contains("pro") ? .pro :
                   tier.rawValue.contains("basic") ? .basic : .free
        }
    }
}

/// Product identifiers for StoreKit
struct SubscriptionProductIDs {
    static let basic = "com.cognote.subscription.basic.v2"
    static let pro = "com.cognote.subscription.pro.v2"
    
    static let all: Set<String> = [basic, pro]
}
