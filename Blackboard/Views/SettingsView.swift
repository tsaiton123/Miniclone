//
//  SettingsView.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/15.
//

import SwiftUI

/// Reusable settings view used in both dashboard and canvas
struct SettingsView: View {
    @EnvironmentObject var subscriptionManager: SubscriptionManager
    @EnvironmentObject var authManager: AuthenticationManager
    @Environment(\.dismiss) private var dismiss
    
    @State private var showingSignOutAlert = false
    @State private var showingDeleteAccountAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Subscription")) {
                    SubscriptionStatusView()
                        .environmentObject(subscriptionManager)
                }
                
                Section(header: Text("Account")) {
                    Button(action: {
                        showingSignOutAlert = true
                    }) {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text("Sign Out")
                        }
                        .foregroundColor(.primary)
                    }
                    
                    Button(action: {
                        showingDeleteAccountAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete Account")
                        }
                        .foregroundColor(.red)
                    }
                }
                
                Section(footer: Text("Deleting your account will permanently remove all your notes and data. This action cannot be undone. Note: App Store subscriptions are managed by Apple and must be cancelled separately in Settings → Apple ID → Subscriptions.")) {
                    EmptyView()
                }
            }
            .alert("Sign Out", isPresented: $showingSignOutAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Sign Out", role: .destructive) {
                    dismiss()
                    authManager.signOut()
                }
            } message: {
                Text("Are you sure you want to sign out?")
            }
            .alert("Delete Account", isPresented: $showingDeleteAccountAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete Account", role: .destructive) {
                    dismiss()
                    authManager.deleteAccount()
                }
            } message: {
                Text("Are you sure you want to delete your account? This will permanently delete all your notes and data. This action cannot be undone.\n\nNote: Your App Store subscription (if any) is tied to your Apple ID and must be cancelled separately in Settings.")
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(SubscriptionManager())
        .environmentObject(AuthenticationManager())
}
