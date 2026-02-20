//
//  AIQuotaManager.swift
//  Blackboard
//
//  Created by Cognote on 2026/01/24.
//

import Foundation
import Combine

/// Manages daily AI usage quota while subscription payments are temporarily disabled
@MainActor
class AIQuotaManager: ObservableObject {
    
    // MARK: - Configuration
    
    /// Daily limit for AI requests
    static let dailyLimit = 20
    
    // MARK: - Published Properties
    
    /// Number of AI requests used today
    @Published private(set) var usedToday: Int = 0
    
    // MARK: - Computed Properties
    
    /// Remaining AI requests for today
    var remainingQuota: Int {
        max(0, Self.dailyLimit - usedToday)
    }
    
    /// Whether the user can make another AI request
    var canMakeRequest: Bool {
        usedToday < Self.dailyLimit
    }
    
    /// Check if user has enough quota for a specific cost
    func hasQuota(cost: Int = 1) -> Bool {
        remainingQuota >= cost
    }
    
    /// Progress percentage (0.0 to 1.0)
    var usageProgress: Double {
        Double(usedToday) / Double(Self.dailyLimit)
    }
    
    // MARK: - Private Properties
    
    private let userDefaults = UserDefaults.standard
    private let usageCountKey = "ai_quota_usage_count"
    private let usageDateKey = "ai_quota_usage_date"
    
    // MARK: - Singleton
    
    static let shared = AIQuotaManager()
    
    // MARK: - Initialization
    
    init() {
        loadUsage()
    }
    
    // MARK: - Public Methods
    
    /// Record an AI request usage
    func recordUsage(cost: Int = 1) {
        guard hasQuota(cost: cost) else { return }
        usedToday += cost
        saveUsage()
        print("[AIQuotaManager] Recorded usage: \(usedToday)/\(Self.dailyLimit)")
    }
    
    /// Check if quota is available and record usage atomically
    /// Returns true if usage was recorded, false if quota exceeded
    func checkAndRecordUsage(cost: Int = 1) -> Bool {
        guard hasQuota(cost: cost) else {
            print("[AIQuotaManager] Quota exceeded: \(usedToday)/\(Self.dailyLimit)")
            return false
        }
        recordUsage(cost: cost)
        return true
    }
    
    /// Force refresh usage from storage (useful when app comes to foreground)
    func refreshUsage() {
        loadUsage()
    }
    
    // MARK: - Private Methods
    
    private func loadUsage() {
        let storedDate = userDefaults.string(forKey: usageDateKey) ?? ""
        let today = todayString()
        
        if storedDate == today {
            // Same day, load existing count
            usedToday = userDefaults.integer(forKey: usageCountKey)
        } else {
            // New day, reset count
            usedToday = 0
            saveUsage()
        }
        
        print("[AIQuotaManager] Loaded usage: \(usedToday)/\(Self.dailyLimit) for \(today)")
    }
    
    private func saveUsage() {
        userDefaults.set(usedToday, forKey: usageCountKey)
        userDefaults.set(todayString(), forKey: usageDateKey)
    }
    
    private func todayString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

// MARK: - Quota Error

enum AIQuotaError: LocalizedError {
    case quotaExceeded
    
    var errorDescription: String? {
        switch self {
        case .quotaExceeded:
            return "Daily AI limit reached. Your quota resets at midnight."
        }
    }
}
