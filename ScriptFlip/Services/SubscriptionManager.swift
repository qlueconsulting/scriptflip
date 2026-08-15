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
        // Safe initialization without unguarded background tasks
        if Purchases.isConfigured {
            Task {
                await fetchCustomerInfo()
            }
        }
    }
    
    /// Configure RevenueCat SDK safely with Public API Key.
    public nonisolated static func configure(apiKey: String) {
        guard !apiKey.isEmpty else {
            print("[SubscriptionManager] Warning: RevenueCat API Key is empty. Skipping configuration.")
            return
        }
        
        guard !Purchases.isConfigured else {
            print("[SubscriptionManager] RevenueCat is already configured.")
            return
        }
        
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
        
        Task { @MainActor in
            await SubscriptionManager.shared.fetchCustomerInfo()
        }
    }
    
    /// Check customer entitlements and active Pro status before every generation request.
    @discardableResult
    public func fetchCustomerInfo() async -> Bool {
        guard Purchases.isConfigured else {
            print("[SubscriptionManager] Purchases not configured yet. Returning fallback entitlement status.")
            #if DEBUG
            self.isPro = UserDefaults.standard.bool(forKey: "DEBUG_SIMULATE_PRO")
            #endif
            return self.isPro
        }
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isPro = customerInfo.entitlements["pro"]?.isActive ?? false
            await fetchOfferings()
            return self.isPro
        } catch {
            print("[SubscriptionManager] Graceful handling - customerInfo fetch error: \(error.localizedDescription)")
            #if DEBUG
            self.isPro = UserDefaults.standard.bool(forKey: "DEBUG_SIMULATE_PRO")
            #endif
            return self.isPro
        }
    }
    
    /// Fetch active RevenueCat offerings safely without throwing or asserting.
    public func fetchOfferings() async {
        guard Purchases.isConfigured else {
            print("[SubscriptionManager] Purchases not configured yet. Skipping fetchOfferings.")
            self.currentOffering = nil
            return
        }
        
        do {
            let offerings = try await Purchases.shared.offerings()
            self.currentOffering = offerings.current
        } catch {
            print("[SubscriptionManager] Graceful handling - offerings fetch error: \(error.localizedDescription)")
            self.currentOffering = nil
        }
    }
    
    /// Purchase a package via RevenueCat.
    public func purchase(package: Package) async -> Bool {
        guard Purchases.isConfigured else {
            self.errorMessage = "In-App Purchases are currently initializing. Please try again in a moment."
            return false
        }
        
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
        guard Purchases.isConfigured else {
            self.errorMessage = "In-App Purchases are currently initializing. Please try again in a moment."
            return false
        }
        
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
