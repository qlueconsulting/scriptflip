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
    public var activeProductIdentifier: String? = nil
    public var activeSubscriptions: Set<String> = []
    public var activeCustomerInfo: CustomerInfo? = nil
    public var currentOffering: Offering? = nil
    public var isPurchasing: Bool = false
    public var errorMessage: String? = nil
    
    private init() {
        // Zero async operations or eager SDK calls in init
    }
    
    // MARK: - TestFlight & Tester Override Detection
    
    /// Detects if running in a Debug build (strictly compiled out in App Store releases).
    public static var isTestFlightOrDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// User-persisted tester override to simulate Pro tier during QA / Diagnostics.
    /// Always returns false in Release/TestFlight — only active in DEBUG builds.
    public static var isTesterOverrideEnabled: Bool {
        get {
            #if DEBUG
            return UserDefaults.standard.bool(forKey: "DEBUG_UNLIMITED_TESTER_MODE")
            #else
            return false
            #endif
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue, forKey: "DEBUG_UNLIMITED_TESTER_MODE")
            #endif
        }
    }
    
    /// User-selected tester override tier. Always returns .free in Release/TestFlight.
    public static var testerOverrideTier: SubscriptionTier {
        get {
            #if DEBUG
            if let saved = UserDefaults.standard.string(forKey: "DEBUG_TESTER_TIER"),
               let tier = SubscriptionTier(rawValue: saved) {
                return tier
            }
            #endif
            return .proWeekly
        }
        set {
            #if DEBUG
            UserDefaults.standard.set(newValue.rawValue, forKey: "DEBUG_TESTER_TIER")
            #endif
        }
    }
    
    /// Resolves the user's active subscription tier (Free, Pro Weekly 50/wk, or Pro Monthly 250/mo).
    public var activeTier: SubscriptionTier {
        if Self.isTesterOverrideEnabled {
            return Self.testerOverrideTier
        }
        guard isPro else {
            return .free
        }
        
        // 1. Gather all candidate product identifiers (active product ID + active subscriptions set + all active entitlements)
        var candidateProductIds: [String] = []
        if let activeId = activeProductIdentifier, !activeId.isEmpty {
            candidateProductIds.append(activeId)
        }
        candidateProductIds.append(contentsOf: activeSubscriptions)
        if let customerInfo = activeCustomerInfo {
            candidateProductIds.append(contentsOf: customerInfo.activeSubscriptions)
            for (_, entitlement) in customerInfo.entitlements.all {
                if entitlement.isActive {
                    candidateProductIds.append(entitlement.productIdentifier)
                    if let planId = entitlement.productPlanIdentifier {
                        candidateProductIds.append(planId)
                    }
                }
            }
        }
        let lowerCandidates = candidateProductIds.map { $0.lowercased() }
        
        // 2. Direct comparison against loaded monthly package product identifier
        if let monthlyProdId = monthlyPackage?.storeProduct.productIdentifier.lowercased() {
            if lowerCandidates.contains(monthlyProdId) {
                return .proMonthly
            }
        }
        
        // 3. Direct comparison against loaded weekly package product identifier
        if let weeklyProdId = weeklyPackage?.storeProduct.productIdentifier.lowercased() {
            if lowerCandidates.contains(weeklyProdId) {
                return .proWeekly
            }
        }
        
        // 4. Inspect all available packages in current offering by packageType & subscriptionPeriod unit
        if let offering = currentOffering {
            for pkg in offering.availablePackages {
                let pkgProdId = pkg.storeProduct.productIdentifier.lowercased()
                if lowerCandidates.contains(pkgProdId) {
                    if pkg.packageType == .monthly || pkg.storeProduct.subscriptionPeriod?.unit == .month {
                        return .proMonthly
                    } else if pkg.packageType == .weekly || pkg.storeProduct.subscriptionPeriod?.unit == .week {
                        return .proWeekly
                    }
                }
            }
        }
        
        // 5. Heuristic search across all candidate IDs for monthly markers (month, monthly, 250, mo)
        for candidate in lowerCandidates {
            if candidate.contains("monthly") || candidate.contains("month") || candidate.contains("250") {
                return .proMonthly
            }
        }
        
        // 6. Heuristic search across all candidate IDs for weekly markers (week, weekly, 50, wk)
        for candidate in lowerCandidates {
            if candidate.contains("weekly") || candidate.contains("week") || candidate.contains("50") {
                return .proWeekly
            }
        }
        
        // 7. Default Pro tier
        return .proWeekly
    }
    
    /// Whether user can upgrade to a higher tier (Free can upgrade to Weekly/Monthly; Weekly can upgrade to Monthly; Monthly is top tier).
    public var canUpgrade: Bool {
        activeTier != .proMonthly
    }
    
    /// Robust lookup for the weekly subscription package
    public var weeklyPackage: Package? {
        guard let offering = currentOffering else { return nil }
        if let pkg = offering.weekly { return pkg }
        return offering.availablePackages.first { pkg in
            pkg.packageType == .weekly ||
            pkg.identifier.lowercased().contains("week") ||
            pkg.storeProduct.productIdentifier.lowercased().contains("week") ||
            pkg.storeProduct.subscriptionPeriod?.unit == .week
        } ?? offering.availablePackages.first
    }
    
    /// Robust lookup for the monthly subscription package
    public var monthlyPackage: Package? {
        guard let offering = currentOffering else { return nil }
        if let pkg = offering.monthly { return pkg }
        return offering.availablePackages.first { pkg in
            pkg.packageType == .monthly ||
            pkg.identifier.lowercased().contains("month") ||
            pkg.storeProduct.productIdentifier.lowercased().contains("month") ||
            pkg.storeProduct.subscriptionPeriod?.unit == .month
        } ?? offering.availablePackages.first { $0 != self.weeklyPackage } ?? offering.availablePackages.last
    }

    /// Filter available packages to strictly show upgrade options (never downgrades).
    public func availableUpgradePackages() -> [Package] {
        guard let packages = currentOffering?.availablePackages else { return [] }
        switch activeTier {
        case .free:
            // Free users see Weekly and Monthly
            return packages
        case .proWeekly:
            // Weekly users only see Monthly upgrade
            if let monthly = monthlyPackage {
                return [monthly]
            }
            return packages.filter { pkg in
                pkg.packageType == .monthly ||
                pkg.identifier.lowercased().contains("month") ||
                pkg.storeProduct.productIdentifier.lowercased().contains("month") ||
                pkg.storeProduct.subscriptionPeriod?.unit == .month
            }
        case .proMonthly:
            // Highest tier: no upgrade options
            return []
        }
    }
    
    /// Determines whether the Pro tier is active (via live RevenueCat Pro entitlement or manual Tester override).
    public var isProTierActive: Bool {
        activeTier != .free
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
        
        // Fetch offerings first so package identifiers & subscription periods are available for tier matching
        await fetchOfferings()
        
        do {
            let customerInfo = try await Purchases.shared.customerInfo()
            self.activeCustomerInfo = customerInfo
            self.activeSubscriptions = customerInfo.activeSubscriptions
            let proEntitlement = customerInfo.entitlements["pro"]
            self.isPro = proEntitlement?.isActive ?? false
            self.activeProductIdentifier = proEntitlement?.productIdentifier ?? customerInfo.activeSubscriptions.first
            DebugLogService.shared.log("[SubscriptionManager] Customer info refreshed. isPro: \(self.isPro), activeTier: \(self.activeTier.rawValue), product: \(self.activeProductIdentifier ?? "none"), allActive: \(customerInfo.activeSubscriptions)")
            return self.isUnlimited
        } catch {
            DebugLogService.shared.log("[SubscriptionManager] Customer info fetch error: \(error.localizedDescription)")
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
            // Robust fallback: use current offering, or offering with identifier "default", or the first available offering in .all
            let resolved = offerings.current ?? offerings["default"] ?? offerings.all.values.first
            self.currentOffering = resolved
            let id = resolved?.identifier ?? "none"
            let count = resolved?.availablePackages.count ?? 0
            DebugLogService.shared.log("[SubscriptionManager] Offerings fetched. Active offering: '\(id)' with \(count) package(s). All offerings: \(Array(offerings.all.keys))")
            print("[SubscriptionManager] Offerings fetched. Active offering: '\(id)' with \(count) package(s).")
        } catch {
            DebugLogService.shared.log("[SubscriptionManager] Offerings fetch error: \(error.localizedDescription)")
            print("[SubscriptionManager] Graceful handling - offerings fetch error: \(error.localizedDescription)")
            self.currentOffering = nil
        }
    }
    
    /// Purchase a package via RevenueCat safely with optional binding.
    public func purchase(package: Package) async -> Bool {
        Self.ensureConfigured()
        
        guard Purchases.isConfigured else {
            #if DEBUG
            self.errorMessage = "In-App Purchases are currently initializing. Please try again in a moment."
            #endif
            return false
        }
        
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        
        do {
            let result = try await Purchases.shared.purchase(package: package)
            if !result.userCancelled {
                self.activeCustomerInfo = result.customerInfo
                self.activeSubscriptions = result.customerInfo.activeSubscriptions
                let proEntitlement = result.customerInfo.entitlements["pro"]
                self.isPro = proEntitlement?.isActive ?? false
                self.activeProductIdentifier = proEntitlement?.productIdentifier ?? result.customerInfo.activeSubscriptions.first
                // Re-run full entitlement & offerings sync
                await fetchCustomerInfo()
                return self.isUnlimited
            }
        } catch {
            #if DEBUG
            self.errorMessage = error.localizedDescription
            #endif
        }
        return false
    }
    
    /// Restore user purchases safely on demand.
    public func restorePurchases() async -> Bool {
        Self.ensureConfigured()
        
        guard Purchases.isConfigured else {
            #if DEBUG
            self.errorMessage = "In-App Purchases are currently initializing. Please try again in a moment."
            #endif
            return false
        }
        
        isPurchasing = true
        errorMessage = nil
        defer { isPurchasing = false }
        
        do {
            let customerInfo = try await Purchases.shared.restorePurchases()
            self.activeCustomerInfo = customerInfo
            self.activeSubscriptions = customerInfo.activeSubscriptions
            let proEntitlement = customerInfo.entitlements["pro"]
            self.isPro = proEntitlement?.isActive ?? false
            self.activeProductIdentifier = proEntitlement?.productIdentifier ?? customerInfo.activeSubscriptions.first
            // Re-run full entitlement & offerings sync
            await fetchCustomerInfo()
            return self.isUnlimited
        } catch {
            #if DEBUG
            self.errorMessage = error.localizedDescription
            #endif
            return false
        }
    }
}
