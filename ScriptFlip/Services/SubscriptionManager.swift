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
    /// Cached resolved tier — set explicitly after every entitlement/offerings refresh.
    /// Avoids the nil-race where currentOffering is nil when activeTier is first read.
    public private(set) var cachedTier: SubscriptionTier = .free
    
    /// User-persisted tester override tier (Free, Pro Weekly, or Pro Monthly) to test limits in Diagnostics.
    public var overrideTier: SubscriptionTier? {
        didSet {
            if let overrideTier {
                UserDefaults.standard.set(overrideTier.rawValue, forKey: "DEBUG_TESTER_TIER")
                UserDefaults.standard.set(true, forKey: "DEBUG_UNLIMITED_TESTER_MODE")
            } else {
                UserDefaults.standard.removeObject(forKey: "DEBUG_TESTER_TIER")
                UserDefaults.standard.set(false, forKey: "DEBUG_UNLIMITED_TESTER_MODE")
            }
        }
    }
    
    private init() {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "DEBUG_UNLIMITED_TESTER_MODE"),
           let saved = UserDefaults.standard.string(forKey: "DEBUG_TESTER_TIER"),
           let tier = SubscriptionTier(rawValue: saved) {
            self.overrideTier = tier
        }
        #endif
    }
    
    // MARK: - Tester Override API
    
    /// Manually switch subscription tier in Diagnostics (Free, Pro Weekly, Pro Monthly).
    public func setTesterOverride(tier: SubscriptionTier) {
        self.overrideTier = tier
        self.cachedTier = tier
    }
    
    /// Clear manual override to restore live Apple / RevenueCat subscription detection.
    public func clearTesterOverride() {
        self.overrideTier = nil
        Task {
            await self.fetchCustomerInfo()
        }
    }
    
    /// Backward-compatible static tester override check.
    public static var isTesterOverrideEnabled: Bool {
        get {
            SubscriptionManager.shared.overrideTier != nil
        }
        set {
            if !newValue {
                SubscriptionManager.shared.overrideTier = nil
            }
        }
    }
    
    /// Backward-compatible static tester override tier.
    public static var testerOverrideTier: SubscriptionTier {
        get {
            SubscriptionManager.shared.overrideTier ?? .proWeekly
        }
        set {
            SubscriptionManager.shared.setTesterOverride(tier: newValue)
        }
    }
    
    /// Detects if running in a Debug build (strictly compiled out in App Store releases).
    public static var isTestFlightOrDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }
    
    /// The user's active subscription tier.
    /// Always use this in the UI — backed by cachedTier with synchronous fallback.
    public var activeTier: SubscriptionTier {
        if let override = overrideTier {
            return override
        }
        guard isPro else {
            return .free
        }
        // If async StoreKit lookup resolved to Pro Monthly, return it immediately
        if cachedTier == .proMonthly {
            return .proMonthly
        }
        // Check synchronous resolution (monthly heuristics, offering packages, activeProductIdentifier)
        let syncTier = resolveSynchronousTier()
        if syncTier == .proMonthly {
            return .proMonthly
        }
        // If cached tier resolved to Pro Weekly and sync didn't detect Monthly, return Pro Weekly
        if cachedTier == .proWeekly {
            return .proWeekly
        }
        return syncTier
    }

    /// Fast, non-blocking synchronous tier evaluation used before async resolution completes or in tests.
    public func resolveSynchronousTier() -> SubscriptionTier {
        if let override = overrideTier {
            return override
        }
        guard isPro else { return .free }
        
        var candidateProductIds: [String] = []
        if let activeId = activeProductIdentifier, !activeId.isEmpty {
            candidateProductIds.append(activeId)
        }
        candidateProductIds.append(contentsOf: activeSubscriptions)
        if let customerInfo = activeCustomerInfo {
            candidateProductIds.append(contentsOf: customerInfo.activeSubscriptions)
            for (_, entitlement) in customerInfo.entitlements.all where entitlement.isActive {
                candidateProductIds.append(entitlement.productIdentifier)
                if let planId = entitlement.productPlanIdentifier {
                    candidateProductIds.append(planId)
                }
            }
        }
        let lower = candidateProductIds.map { $0.lowercased() }
        
        // 1. Check direct match against monthly package product ID
        if let monthlyId = monthlyPackage?.storeProduct.productIdentifier.lowercased(), !monthlyId.isEmpty {
            if lower.contains(monthlyId) {
                return .proMonthly
            }
        }
        
        // 2. Monthly string heuristic FIRST (Monthly always takes precedence)
        for c in lower {
            if c.contains("monthly") || c.contains("month") || c.contains("250") || c.contains("mo") {
                return .proMonthly
            }
        }
        
        // 3. Check direct match against weekly package product ID
        if let weeklyId = weeklyPackage?.storeProduct.productIdentifier.lowercased(), !weeklyId.isEmpty {
            if lower.contains(weeklyId) {
                return .proWeekly
            }
        }
        
        // 4. Weekly string heuristic
        for c in lower {
            if c.contains("weekly") || c.contains("week") || c.contains("50") || c.contains("wk") {
                return .proWeekly
            }
        }
        
        // Default for verified Pro users when cadence cannot be parsed
        return .proMonthly
    }

    /// Resolves and caches the active subscription tier from current RevenueCat state.
    /// Priority order:
    /// 1. StoreKit 2 actual subscriptionPeriod unit (.month vs .week) & price inspection
    /// 2. Current Offering available packages matching
    /// 3. String heuristics on all candidate IDs (Monthly takes precedence)
    /// 4. Safe default to Pro Monthly for verified paying subscribers
    private func resolveActiveTier() async {
        if let override = overrideTier {
            cachedTier = override
            return
        }
        guard isPro else {
            cachedTier = .free
            return
        }

        // Gather unique candidate product identifiers from all RevenueCat sources
        var candidateProductIds: [String] = []
        if let activeId = activeProductIdentifier, !activeId.isEmpty {
            candidateProductIds.append(activeId)
        }
        candidateProductIds.append(contentsOf: activeSubscriptions)
        if let customerInfo = activeCustomerInfo {
            candidateProductIds.append(contentsOf: customerInfo.activeSubscriptions)
            for (_, entitlement) in customerInfo.entitlements.all where entitlement.isActive {
                candidateProductIds.append(entitlement.productIdentifier)
                if let planId = entitlement.productPlanIdentifier {
                    candidateProductIds.append(planId)
                }
            }
        }
        let uniqueCandidates = Array(Set(candidateProductIds)).filter { !$0.isEmpty }
        let lowerCandidates = uniqueCandidates.map { $0.lowercased() }
        DebugLogService.shared.log("[SubscriptionManager] resolveActiveTier — candidates: \(uniqueCandidates)")

        // PRIORITY 1: Ask StoreKit for the actual subscription period & price of each candidate product.
        // MONTHLY MUST ALWAYS TAKE PRECEDENCE OVER WEEKLY IF BOTH ARE PRESENT.
        if !uniqueCandidates.isEmpty, Purchases.isConfigured {
            do {
                let storeProducts = try await Purchases.shared.products(uniqueCandidates)
                DebugLogService.shared.log("[SubscriptionManager] StoreKit products returned: \(storeProducts.map { "\($0.productIdentifier) period=\(String(describing: $0.subscriptionPeriod?.unit.rawValue)) price=\($0.price)" })")
                
                // Check if ANY product is Monthly (by unit == .month or price > $10, e.g. $19.99 vs $4.99)
                let hasMonthlyProduct = storeProducts.contains { product in
                    product.subscriptionPeriod?.unit == .month || product.price > 10.0
                }
                if hasMonthlyProduct {
                    cachedTier = .proMonthly
                    DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (StoreKit detected month period or monthly price threshold)")
                    return
                }
                
                // If NO Monthly product found, check if ANY product is Weekly
                let hasWeeklyProduct = storeProducts.contains { product in
                    product.subscriptionPeriod?.unit == .week
                }
                if hasWeeklyProduct {
                    cachedTier = .proWeekly
                    DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (StoreKit detected week period)")
                    return
                }
            } catch {
                DebugLogService.shared.log("[SubscriptionManager] StoreKit products fetch failed: \(error.localizedDescription) — falling back to offering matching")
            }
        }

        // PRIORITY 2: Match against offering packages (Monthly checked FIRST)
        if let offering = currentOffering {
            let hasMonthlyOffering = offering.availablePackages.contains { pkg in
                let pkgProdId = pkg.storeProduct.productIdentifier.lowercased()
                guard lowerCandidates.contains(pkgProdId) else { return false }
                return pkg.packageType == .monthly || pkg.storeProduct.subscriptionPeriod?.unit == .month || pkg.storeProduct.price > 10.0
            }
            if hasMonthlyOffering {
                cachedTier = .proMonthly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (Offering detected monthly package)")
                return
            }
            
            let hasWeeklyOffering = offering.availablePackages.contains { pkg in
                let pkgProdId = pkg.storeProduct.productIdentifier.lowercased()
                guard lowerCandidates.contains(pkgProdId) else { return false }
                return pkg.packageType == .weekly || pkg.storeProduct.subscriptionPeriod?.unit == .week
            }
            if hasWeeklyOffering {
                cachedTier = .proWeekly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (Offering detected weekly package)")
                return
            }
        }

        // PRIORITY 3: String heuristics on candidate product IDs (Monthly checked FIRST)
        for candidate in lowerCandidates {
            if candidate.contains("monthly") || candidate.contains("month") || candidate.contains("250") || candidate.contains("mo") {
                cachedTier = .proMonthly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (string heuristic: '\(candidate)')")
                return
            }
        }
        for candidate in lowerCandidates {
            if candidate.contains("weekly") || candidate.contains("week") || candidate.contains("50") || candidate.contains("wk") {
                cachedTier = .proWeekly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (string heuristic: '\(candidate)')")
                return
            }
        }

        // PRIORITY 4: Verified Pro customer whose cadence cannot be determined from metadata
        DebugLogService.shared.log("[SubscriptionManager] Indeterminate Pro cadence for candidates: \(uniqueCandidates). Defaulting to proMonthly (250/mo) for verified paying subscriber.")
        cachedTier = .proMonthly
    }


    /// Whether user can upgrade to a higher tier (Free can upgrade to Weekly/Monthly; Weekly can upgrade to Monthly; Monthly is top tier).
    public var canUpgrade: Bool {
        activeTier != .proMonthly
    }
    
    /// Returns the weekly subscription package from the current offering, or nil if not found.
    public var weeklyPackage: Package? {
        guard let offering = currentOffering else { return nil }
        if let pkg = offering.weekly { return pkg }
        return offering.availablePackages.first { pkg in
            pkg.packageType == .weekly ||
            pkg.identifier.lowercased().contains("week") ||
            pkg.storeProduct.productIdentifier.lowercased().contains("week") ||
            pkg.storeProduct.subscriptionPeriod?.unit == .week
        }
        // No fallback to .first — returning nil is safer than returning the wrong package
    }

    /// Returns the monthly subscription package from the current offering, or nil if not found.
    public var monthlyPackage: Package? {
        guard let offering = currentOffering else { return nil }
        if let pkg = offering.monthly { return pkg }
        return offering.availablePackages.first { pkg in
            pkg.packageType == .monthly ||
            pkg.identifier.lowercased().contains("month") ||
            pkg.storeProduct.productIdentifier.lowercased().contains("month") ||
            pkg.storeProduct.subscriptionPeriod?.unit == .month
        }
        // No fallback to .last — returning nil is safer than returning the wrong package
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
            // Force sync with App Store receipt so upgrades made in Settings or outside app are recognized
            let customerInfo: CustomerInfo
            if let synced = try? await Purchases.shared.syncPurchases() {
                customerInfo = synced
            } else {
                customerInfo = try await Purchases.shared.customerInfo()
            }
            self.activeCustomerInfo = customerInfo
            self.activeSubscriptions = customerInfo.activeSubscriptions
            let proEntitlement = customerInfo.entitlements["pro"]
            self.isPro = proEntitlement?.isActive ?? false
            self.activeProductIdentifier = proEntitlement?.productIdentifier ?? customerInfo.activeSubscriptions.first
            
            // If live RevenueCat entitlement is active, disable any stale tester override so real subscription takes precedence
            if self.isPro {
                self.overrideTier = nil
                UserDefaults.standard.removeObject(forKey: "DEBUG_TESTER_TIER")
                UserDefaults.standard.set(false, forKey: "DEBUG_UNLIMITED_TESTER_MODE")
            }
            
            // Resolve and cache the tier now that both customerInfo and currentOffering are set
            await self.resolveActiveTier()
            DebugLogService.shared.log("[SubscriptionManager] Customer info refreshed. isPro: \(self.isPro), resolvedTier: \(self.cachedTier.rawValue), product: \(self.activeProductIdentifier ?? "none"), allActive: \(customerInfo.activeSubscriptions)")
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
