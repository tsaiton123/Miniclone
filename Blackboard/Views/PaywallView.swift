//
//  PaywallView.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/03.
//

import SwiftUI
import StoreKit

/// Paywall view for subscription purchase
struct PaywallView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var selectedProduct: Product?
    @State private var isPurchasing = false
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Header
                    headerSection
                    
                    // Feature comparison
                    featureComparisonSection
                    
                    // Subscription options
                    subscriptionOptionsSection
                    
                    // Purchase button
                    purchaseButtonSection
                    
                    // Restore & Terms
                    footerSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Upgrade to Premium")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Pre-select basic plan by default if products already loaded
            if selectedProduct == nil, let first = subscriptionManager.products.first {
                selectedProduct = first
            }
        }
        .onChange(of: subscriptionManager.products) { _, newProducts in
            // Auto-select first product when products finish loading
            if selectedProduct == nil, let first = newProducts.first {
                selectedProduct = first
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))
                .foregroundStyle(.linearGradient(
                    colors: [.purple, .blue],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Text("Unlock Cognote")
                .font(.title)
                .fontWeight(.bold)
            
            Text("Get unlimited notes, PDF import, and AI-powered features")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top)
    }
    
    // MARK: - Feature Comparison Section
    
    private var featureComparisonSection: some View {
        VStack(spacing: 0) {
            // Header row with plan names
            HStack {
                Text("Features")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
                
                Text("Free")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.secondary)
                    .frame(width: 60)
                
                Text("Basic")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                    .frame(width: 60)
                
                Text("Pro")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundColor(.purple)
                    .frame(width: 60)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            
            Divider()
            featureRow(icon: "doc.text", title: "Notes", free: "3 max", basic: "Unlimited", pro: "Unlimited")
            Divider()
            featureRow(icon: "doc.richtext", title: "PDF Import", free: false, basic: true, pro: true)
            Divider()
            featureRow(icon: "brain.head.profile", title: "AI Features", free: false, basic: false, pro: true)
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
    }
    
    private func featureRow(icon: String, title: String, free: String, basic: String, pro: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            Text(free)
                .frame(width: 60)
                .foregroundColor(.secondary)
            
            Text(basic)
                .frame(width: 60)
                .foregroundColor(.blue)
            
            Text(pro)
                .frame(width: 60)
                .foregroundColor(.purple)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func featureRow(icon: String, title: String, free: Bool, basic: Bool, pro: Bool) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            checkmark(free)
                .frame(width: 60)
            
            checkmark(basic)
                .frame(width: 60)
            
            checkmark(pro)
                .frame(width: 60)
        }
        .font(.footnote)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
    
    private func checkmark(_ available: Bool) -> some View {
        Image(systemName: available ? "checkmark.circle.fill" : "xmark.circle")
            .foregroundColor(available ? .green : .secondary.opacity(0.5))
    }
    
    // MARK: - Subscription Options Section
    
    private var subscriptionOptionsSection: some View {
        VStack(spacing: 12) {
            ForEach(subscriptionManager.products, id: \.id) { product in
                SubscriptionOptionCard(
                    product: product,
                    isSelected: selectedProduct?.id == product.id,
                    onSelect: { selectedProduct = product }
                )
            }
        }
    }
    
    // MARK: - Purchase Button Section
    
    private var purchaseButtonSection: some View {
        VStack(spacing: 12) {
            Button(action: {
                Task {
                    await purchaseSelected()
                }
            }) {
                HStack {
                    if isPurchasing {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text(purchaseButtonTitle)
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(
                    LinearGradient(
                        colors: selectedProduct?.id.contains("pro") == true
                            ? [.purple, .pink]
                            : [.blue, .cyan],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .foregroundColor(.white)
                .cornerRadius(14)
            }
            .disabled(selectedProduct == nil || isPurchasing)
            
            if let product = selectedProduct, product.id == SubscriptionProductIDs.basic {
                Text("Start with 1 month free trial")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var purchaseButtonTitle: String {
        guard let product = selectedProduct else {
            return "Select a Plan"
        }
        
        if product.id == SubscriptionProductIDs.basic {
            return "Start Free Trial"
        } else {
            return "Subscribe for \(product.displayPrice)/month"
        }
    }
    
    // MARK: - Footer Section
    
    private var footerSection: some View {
        VStack(spacing: 16) {
            Button("Restore Purchases") {
                Task {
                    await subscriptionManager.restorePurchases()
                }
            }
            .font(.subheadline)
            .foregroundColor(.secondary)
            
            Text("Subscriptions auto-renew monthly until cancelled. Cancel anytime in Settings.")
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Link("Terms of Service", destination: URL(string: "https://cognote.app/terms")!)
                Link("Privacy Policy", destination: URL(string: "https://cognote.app/privacy")!)
            }
            .font(.caption2)
        }
        .padding(.top)
    }
    
    // MARK: - Actions
    
    private func purchaseSelected() async {
        guard let product = selectedProduct else { return }
        
        isPurchasing = true
        
        let success = await subscriptionManager.purchase(product)
        
        isPurchasing = false
        
        if success {
            // Small delay to allow the subscription status to update before dismissing
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            dismiss()
        }
    }
}

// MARK: - Subscription Option Card

struct SubscriptionOptionCard: View {
    let product: Product
    let isSelected: Bool
    let onSelect: () -> Void
    
    private var isPro: Bool {
        product.id.contains("pro")
    }
    
    private var hasFreeTrial: Bool {
        product.id == SubscriptionProductIDs.basic
    }
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(isPro ? "Pro" : "Basic")
                            .font(.headline)
                        
                        if hasFreeTrial {
                            Text("1 MONTH FREE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.green)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                        
                        if isPro {
                            Text("BEST VALUE")
                                .font(.caption2)
                                .fontWeight(.bold)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.purple)
                                .foregroundColor(.white)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(isPro ? "All features including AI" : "Unlimited notes & PDF")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing) {
                    Text(product.displayPrice)
                        .font(.title3)
                        .fontWeight(.semibold)
                    Text("/month")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? (isPro ? Color.purple : Color.blue) : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    PaywallView()
        .environmentObject(SubscriptionManager())
}
