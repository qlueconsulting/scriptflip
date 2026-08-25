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
        // Zero async operations or eager SDK calls in init
    }
    
    // MARK: - TestFlight & Tester Override Detection
    
    /// Detects if running in a Debug build or TestFlight sandbox environment.
    public static var isTestFlightOrDebug: Bool {
        #if DEBUG
        return true
        #else
        guard let url = Bundle.main.appStoreReceiptURL else { return false }
        return url.lastPathComponent == "sandboxReceipt"
        #endif
    }
    
    /// User-persisted tester override to simulate Pro tier during QA / Diagnostics.
    public static var isTesterOverrideEnabled: Bool {
        get {
            UserDefaults.standard.bool(forKey: "DEBUG_UNLIMITED_TESTER_MODE")
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "DEBUG_UNLIMITED_TESTER_MODE")
        }
    }
    
    /// Determines whether the Pro tier is active (via live RevenueCat Pro entitlement or manual Tester override).
    public var isProTierActive: Bool {
        isPro || Self.isTesterOverrideEnabled
    }
    
    /// Backward-compatible alias for Pro tier status.
    public var isUnlimited: Bool {
        isProTierActive
    }
    
    // MARK: - SDK Lifecycle
    
    /// Lazily configure RevenueCat SDK safely on demand without blocking app launch.
    public nonisolated static func ensureConfigured() {
        let apiKey = AppEnvironment.revenueCatAPIKey
        guard !apiKey.isEmpty else {
            print("[SubscriptionManager] Warning: RevenueCat API Key is empty. Skipping configuration.")
            return
        }
        
        guard !Purchases.isConfigured else {
            return
        }
        
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }
    
    /// Configure RevenueCat SDK safely with Public API Key.
    public nonisolated static func configure(apiKey: String) {
        guard !apiKey.isEmpty else { return }
        guard !Purchases.isConfigured else { return }
        Purchases.logLevel = .warn
        Purchases.configure(withAPIKey: apiKey)
    }
    
    /// Check customer entitlements and active Pro status on demand.
    @discardableResult
    public func fetchCustomerInfo() async -> Bool {
        Self.ensureConfigured()
        
        guard Purchases.isConfigured else {
            print("[SubscriptionManager] Purchases not configured. Returning entitlement status.")
            return self.isUnlimited
        }
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.isPro = customerInfo.entitlements["pro"]?.isActive ?? false
            await fetchOfferings()
            return self.isUnlimited
        } catch {
            print("[SubscriptionManager] Graceful handling - customerInfo fetch error: \(error.localizedDescription)")
            return self.isUnlimited
        }
    }
    
    /// Fetch active RevenueCat offerings safely on demand without throwing or asserting.
    public func fetchOfferings() async {
        Self.ensureConfigured()
        
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
    
    /// Purchase a package via RevenueCat safely with optional binding.
    public func purchase(package: Package) async -> Bool {
        Self.ensureConfigured()
        
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
                return self.isUnlimited
            }
        } catch {
            self.errorMessage = error.localizedDescription
        }
        return false
    }
    
    /// Restore user purchases safely on demand.
    public func restorePurchases() async -> Bool {
        Self.ensureConfigured()
        
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
            return self.isUnlimited
        } catch {
            self.errorMessage = error.localizedDescription
            return false
        }
    }
}
