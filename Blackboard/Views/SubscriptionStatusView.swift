//
//  SubscriptionStatusView.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/03.
//

import SwiftUI

/// View to display current subscription status in settings
struct SubscriptionStatusView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @State private var showingPaywall = false
    
    var body: some View {
        VStack(spacing: 16) {
            // Current Plan Card
            currentPlanCard
            
            // Upgrade Button (if not on highest tier)
            if subscriptionManager.currentTier != .pro {
                upgradeButton
            }
            
            // Manage Subscription Link
            if subscriptionManager.currentTier != .free {
                manageSubscriptionLink
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
                .environmentObject(subscriptionManager)
        }
    }
    
    // MARK: - Current Plan Card
    
    private var currentPlanCard: some View {
        VStack(spacing: 12) {
            HStack {
                tierIcon
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Plan")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Cognote \(subscriptionManager.currentTier.displayName)")
                        .font(.headline)
                }
                
                Spacer()
                
                tierBadge
            }
            
            Divider()
            
            // Features list
            VStack(alignment: .leading, spacing: 8) {
                featureItem(
                    "Notes",
                    value: subscriptionManager.currentTier.hasUnlimitedNotes ? "Unlimited" : "3 max",
                    available: true
                )
                featureItem(
                    "PDF Import",
                    value: subscriptionManager.currentTier.hasPDFImport ? "Included" : "Not available",
                    available: subscriptionManager.currentTier.hasPDFImport
                )
                featureItem(
                    "AI Features",
                    value: subscriptionManager.currentTier.hasAIFeatures ? "Included" : "Not available",
                    available: subscriptionManager.currentTier.hasAIFeatures
                )
            }
            
            // Expiration date if subscribed
            if case .subscribed(_, let expirationDate) = subscriptionManager.subscriptionStatus,
               let date = expirationDate {
                Divider()
                HStack {
                    Text("Renews")
                        .foregroundColor(.secondary)
                    Spacer()
                    Text(date, style: .date)
                }
                .font(.caption)
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private var tierIcon: some View {
        Image(systemName: tierIconName)
            .font(.title)
            .foregroundStyle(tierGradient)
            .frame(width: 44, height: 44)
            .background(tierGradient.opacity(0.15))
            .cornerRadius(10)
    }
    
    private var tierIconName: String {
        switch subscriptionManager.currentTier {
        case .free: return "person"
        case .basic: return "star"
        case .pro: return "sparkles"
        }
    }
    
    private var tierGradient: LinearGradient {
        switch subscriptionManager.currentTier {
        case .free:
            return LinearGradient(colors: [.gray], startPoint: .top, endPoint: .bottom)
        case .basic:
            return LinearGradient(colors: [.blue, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .pro:
            return LinearGradient(colors: [.purple, .pink], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    private var tierBadge: some View {
        Text(subscriptionManager.currentTier.displayName.uppercased())
            .font(.caption2)
            .fontWeight(.bold)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tierGradient)
            .foregroundColor(.white)
            .cornerRadius(6)
    }
    
    private func featureItem(_ title: String, value: String, available: Bool) -> some View {
        HStack {
            Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(available ? .green : .secondary.opacity(0.5))
                .font(.caption)
            
            Text(title)
                .font(.subheadline)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Upgrade Button
    
    private var upgradeButton: some View {
        Button(action: { showingPaywall = true }) {
            HStack {
                Image(systemName: "arrow.up.circle.fill")
                Text(subscriptionManager.currentTier == .free ? "Upgrade to Premium" : "Upgrade to Pro")
            }
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding()
            .background(
                LinearGradient(
                    colors: subscriptionManager.currentTier == .free
                        ? [.blue, .cyan]
                        : [.purple, .pink],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
    
    // MARK: - Manage Subscription Link
    
    private var manageSubscriptionLink: some View {
        Button(action: openSubscriptionManagement) {
            HStack {
                Image(systemName: "gear")
                Text("Manage Subscription")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.subheadline)
            .foregroundColor(.primary)
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
    }
    
    private func openSubscriptionManagement() {
        if let url = URL(string: "https://apps.apple.com/account/subscriptions") {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    SubscriptionStatusView()
        .environmentObject(SubscriptionManager())
        .padding()
        .background(Color(.systemGroupedBackground))
}
