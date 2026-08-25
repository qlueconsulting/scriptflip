import Foundation

/// Models Free tier (3/mo) and Pro tier (50/wk, 250/mo) user quotas and limits.
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
    
    public var isProLimitReached: Bool {
        isProWeeklyLimitReached || isProMonthlyLimitReached
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
