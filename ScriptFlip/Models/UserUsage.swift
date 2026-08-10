import Foundation

/// Models monthly user quota and limits.
public struct UserUsage: Codable, Sendable {
    public static let freeMonthlyLimit: Int = 3
    
    public var usedCount: Int
    public var lastResetDate: Date
    
    public init(usedCount: Int = 0, lastResetDate: Date = Date()) {
        self.usedCount = usedCount
        self.lastResetDate = lastResetDate
    }
    
    public var remainingFreeGenerations: Int {
        max(0, Self.freeMonthlyLimit - usedCount)
    }
    
    public var isLimitReached: Bool {
        usedCount >= Self.freeMonthlyLimit
    }
}
