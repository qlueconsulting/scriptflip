import Foundation

/// Persistent monthly usage tracker enforcing the 3 free generations limit per month.
public final class UsageTracker: Sendable {
    public static let shared = UsageTracker()
    
    private let userDefaultsKey = "com.scriptflip.userUsage"
    
    private init() {}
    
    /// Get current usage, resetting count if a new calendar month has started.
    public func getUsage() -> UserUsage {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey) else {
            let initial = UserUsage()
            saveUsage(initial)
            return initial
        }
        
        do {
            let usage = try JSONDecoder().decode(UserUsage.self, from: data)
            
            // Check if calendar month has changed
            let calendar = Calendar.current
            if !calendar.isDate(usage.lastResetDate, equalTo: Date(), toGranularity: .month) {
                let resetUsage = UserUsage(usedCount: 0, lastResetDate: Date())
                saveUsage(resetUsage)
                return resetUsage
            }
            
            return usage
        } catch {
            print("[UsageTracker] Error decoding saved usage data: \(error.localizedDescription). Resetting to initial usage.")
            let fallback = UserUsage()
            saveUsage(fallback)
            return fallback
        }
    }
    
    /// Increment usage count after successful script generation.
    @discardableResult
    public func incrementUsage() -> UserUsage {
        var current = getUsage()
        current.usedCount += 1
        saveUsage(current)
        return current
    }
    
    /// Reset usage (useful for testing or Pro status upgrades).
    public func resetUsage() {
        let reset = UserUsage(usedCount: 0, lastResetDate: Date())
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
