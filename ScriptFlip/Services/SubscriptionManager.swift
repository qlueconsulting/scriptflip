import Foundation
import Observation
import RevenueCat
import RevenueCatUI

/// Observable Subscription & Paywall Manager using RevenueCat SDK.
@Observable
@MainActor
public final class SubscriptionManager {
    public static let shared = SubscriptionManager()
    
    public var isPro: Bool = false
    public var currentOffering: Offering? = nil
    public var isPurchasing: Bool = false
    public var errorMessage: String? = nil
    
    private init() {
        // Automatically fetch entitlement status on init
        Task {
            await fetchCustomerInfo()
        }
    }
    
    /// Configure RevenueCat SDK with Public API Key.
    public nonisolated static func configure(apiKey: String) {
        Purchases.logLevel = .debug
        Purchases.configure(withAPIKey: apiKey)
    }
    
    /// Check customer entitlements and active Pro status before every generation request.
    @discardableResult
    public func fetchCustomerInfo() async -> Bool {
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isPro = customerInfo.entitlements["pro"]?.isActive ?? false
            await fetchOfferings()
            return self.isPro
        } catch {
            print("[SubscriptionManager] Error fetching customer info: \(error.localizedDescription)")
            #if DEBUG
            self.isPro = UserDefaults.standard.bool(forKey: "DEBUG_SIMULATE_PRO")
            #endif
            return self.isPro
        }
    }
    
    /// Fetch active RevenueCat offerings.
    public func fetchOfferings() async {
        do {
            let offerings = try await Purchases.shared.offerings()
            self.currentOffering = offerings.current
        } catch {
            print("[SubscriptionManager] Error fetching offerings: \(error.localizedDescription)")
        }
    }
    
    /// Purchase a package via RevenueCat.
    public func purchase(package: Package) async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                self.isPro = result.customerInfo.entitlements["pro"]?.isActive ?? false
                return self.isPro
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        return false
    }
    
    /// Restore user purchases.
    public func restorePurchases() async -> Bool {
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            self.isPro = customerInfo.entitlements["pro"]?.isActive ?? false
            return self.isPro
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}
