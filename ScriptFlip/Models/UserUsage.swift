import Foundation

/// Subscription tiers supported by ScriptFlip with distinct quota limits.
public enum SubscriptionTier: String, Codable, Sendable, CaseIterable {
    case free = "Free"
    case proWeekly = "Pro Weekly"
    case proMonthly = "Pro Monthly"
    
    public var displayName: String {
        switch self {
        case .free: return "Free (3 / month)"
        case .proWeekly: return "Pro Weekly (50 / week)"
        case .proMonthly: return "Pro Monthly (250 / month)"
        }
    }
}

/// Models Free tier (3/mo), Pro Weekly (50/wk), and Pro Monthly (250/mo) user quotas and limits.
public struct UserUsage: Codable, Sendable {
    public static let freeMonthlyLimit: Int = 3
    public static let proWeeklyLimit: Int = 50
    public static let proMonthlyLimit: Int = 250
    
    // Free tier tracking
    public var usedCount: Int
    public var lastResetDate: Date
    
    // Pro tier tracking
    public var proUsedThisWeek: Int
    public var proUsedThisMonth: Int
    public var lastWeekResetDate: Date
    
    public init(
        usedCount: Int = 0,
        lastResetDate: Date = Date(),
        proUsedThisWeek: Int = 0,
        proUsedThisMonth: Int = 0,
        lastWeekResetDate: Date = Date()
    ) {
        self.usedCount = usedCount
        self.lastResetDate = lastResetDate
        self.proUsedThisWeek = proUsedThisWeek
        self.proUsedThisMonth = proUsedThisMonth
        self.lastWeekResetDate = lastWeekResetDate
    }
    
    // MARK: - Tier-Specific Quota Evaluation
    
    public func remainingGenerations(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free:
            return remainingFreeGenerations
        case .proWeekly:
            return remainingProWeeklyGenerations
        case .proMonthly:
            return remainingProMonthlyGenerations
        }
    }
    
    public func isLimitReached(for tier: SubscriptionTier) -> Bool {
        switch tier {
        case .free:
            return isLimitReached
        case .proWeekly:
            return isProWeeklyLimitReached
        case .proMonthly:
            return isProMonthlyLimitReached
        }
    }
    
    public func totalLimit(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return Self.freeMonthlyLimit
        case .proWeekly: return Self.proWeeklyLimit
        case .proMonthly: return Self.proMonthlyLimit
        }
    }
    
    public func usedGenerations(for tier: SubscriptionTier) -> Int {
        switch tier {
        case .free: return usedCount
        case .proWeekly: return proUsedThisWeek
        case .proMonthly: return proUsedThisMonth
        }
    }
    
    public func cadenceUnit(for tier: SubscriptionTier) -> String {
        switch tier {
        case .free: return "Free"
        case .proWeekly: return "Wk"
        case .proMonthly: return "Mo"
        }
    }
    
    /// User-facing remaining quota formatted string: e.g. "250/250 Mo", "50/50 Wk", "3/3 Free"
    public func remainingQuotaString(for tier: SubscriptionTier) -> String {
        "\(remainingGenerations(for: tier))/\(totalLimit(for: tier)) \(cadenceUnit(for: tier))"
    }
    
    /// User-facing badge formatted string: e.g. "PRO (250/250 Mo)", "PRO (50/50 Wk)", "3/3 Free Left"
    public func badgeQuotaString(for tier: SubscriptionTier) -> String {
        switch tier {
        case .proMonthly:
            return "PRO (\(remainingProMonthlyGenerations)/250 Mo)"
        case .proWeekly:
            return "PRO (\(remainingProWeeklyGenerations)/50 Wk)"
        case .free:
            return "\(remainingFreeGenerations)/3 Free Left"
        }
    }
    
    // MARK: - Free Tier Computations
    
    public var remainingFreeGenerations: Int {
        max(0, Self.freeMonthlyLimit - usedCount)
    }
    
    public var isLimitReached: Bool {
        usedCount >= Self.freeMonthlyLimit
    }
    
    // MARK: - Pro Tier Computations
    
    public var remainingProWeeklyGenerations: Int {
        max(0, Self.proWeeklyLimit - proUsedThisWeek)
    }
    
    public var remainingProMonthlyGenerations: Int {
        max(0, Self.proMonthlyLimit - proUsedThisMonth)
    }
    
    public var isProWeeklyLimitReached: Bool {
        proUsedThisWeek >= Self.proWeeklyLimit
    }
    
    public var isProMonthlyLimitReached: Bool {
        proUsedThisMonth >= Self.proMonthlyLimit
    }
    
    /// Checks if Pro quota is reached for the given tier without conflating weekly and monthly quotas.
    public func isProLimitReached(for tier: SubscriptionTier) -> Bool {
        switch tier {
        case .proMonthly:
            return isProMonthlyLimitReached
        case .proWeekly:
            return isProWeeklyLimitReached
        case .free:
            return isLimitReached
        }
    }
    
    @available(*, deprecated, message: "Use isLimitReached(for: tier) to avoid conflating weekly and monthly quotas.")
    public var isProLimitReached: Bool {
        isProWeeklyLimitReached
    }
    
    // MARK: - Backward Compatibility Decoding
    
    private enum CodingKeys: String, CodingKey {
        case usedCount
        case lastResetDate
        case proUsedThisWeek
        case proUsedThisMonth
        case lastWeekResetDate
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.usedCount = try container.decodeIfPresent(Int.self, forKey: .usedCount) ?? 0
        self.lastResetDate = try container.decodeIfPresent(Date.self, forKey: .lastResetDate) ?? Date()
        self.proUsedThisWeek = try container.decodeIfPresent(Int.self, forKey: .proUsedThisWeek) ?? 0
        self.proUsedThisMonth = try container.decodeIfPresent(Int.self, forKey: .proUsedThisMonth) ?? 0
        self.lastWeekResetDate = try container.decodeIfPresent(Date.self, forKey: .lastWeekResetDate) ?? Date()
    }
}
