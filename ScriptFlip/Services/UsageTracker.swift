import Foundation

/// Persistent usage tracker enforcing Free limits (3/mo) and Pro limits (50/wk, 250/mo).
public final class UsageTracker: Sendable {
    public static let shared = UsageTracker()
    
    private let userDefaultsKey = "com.scriptflip.userUsage"
    
    private init() {}
    
    /// Get current usage, resetting weekly / monthly quotas if calendar intervals have rolled over.
    public func getUsage() -> UserUsage {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            let initial = UserUsage()
            saveUsage(initial)
            return initial
        }
        
        do {
            var usage = try JSONDecoder().decode(UserUsage.self, from: data)
            let calendar = Calendar.current
            let now = Date()
            var modified = false
            
            // Check if calendar month has changed
            if !calendar.isDate(usage.lastResetDate, equalTo: now, toGranularity: .month) {
                usage.usedCount = 0
                usage.proUsedThisMonth = 0
                usage.lastResetDate = now
                modified = true
            }
            
            // Check if calendar week has changed
            if !calendar.isDate(usage.lastWeekResetDate, equalTo: now, toGranularity: .weekOfYear) {
                usage.proUsedThisWeek = 0
                usage.lastWeekResetDate = now
                modified = true
            }
            
            if modified {
                saveUsage(usage)
            }
            
            return usage
        } catch {
            print("[UsageTracker] Error decoding saved usage data: \(error.localizedDescription). Resetting to initial usage.")
            let fallback = UserUsage()
            saveUsage(fallback)
            return fallback
        }
    }
    
    /// Increment usage count after successful script generation based on active subscription tier.
    @discardableResult
    public func incrementUsage(tier: SubscriptionTier) -> UserUsage {
        var current = getUsage()
        switch tier {
        case .free:
            current.usedCount += 1
        case .proWeekly:
            current.proUsedThisWeek += 1
        case .proMonthly:
            current.proUsedThisMonth += 1
        }
        saveUsage(current)
        return current
    }
    
    /// Backward-compatible overload for boolean isPro parameter.
    @discardableResult
    public func incrementUsage(isPro: Bool = false) -> UserUsage {
        incrementUsage(tier: isPro ? .proWeekly : .free)
    }
    
    /// Reset all Free and Pro usage quotas (useful for diagnostics or testing).
    public func resetUsage() {
        let reset = UserUsage(
            usedCount: 0,
            lastResetDate: Date(),
            proUsedThisWeek: 0,
            proUsedThisMonth: 0,
            lastWeekResetDate: Date()
        )
        saveUsage(reset)
    }
    
    private func saveUsage(_ usage: UserUsage) {
        do {
            let encoded = try JSONEncoder().encode(usage)
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        } catch {
            print("[UsageTracker] Error encoding usage data: \(error.localizedDescription)")
        }
    }
}
