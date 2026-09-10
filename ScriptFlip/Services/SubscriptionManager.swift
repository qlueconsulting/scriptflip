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
    
    /// The user's active subscription tier.
    /// Always use this in the UI — backed by cachedTier which is set after every RevenueCat refresh.
    public var activeTier: SubscriptionTier {
        if Self.isTesterOverrideEnabled {
            return Self.testerOverrideTier
        }
        return cachedTier
    }

    /// Resolves and caches the active subscription tier from current RevenueCat state.
    /// Uses StoreKit subscription period via Purchases.shared.products() as the
    /// primary detection strategy — reliable regardless of product ID naming or package ordering.
    /// Falls back to offering package type matching and then string heuristics.
    private func resolveActiveTier() async {
        if Self.isTesterOverrideEnabled {
            cachedTier = Self.testerOverrideTier
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
        DebugLogService.shared.log("[SubscriptionManager] resolveActiveTier — candidates: \(uniqueCandidates)")

        // PRIMARY: Ask StoreKit for the actual subscription period of each candidate product.
        // This is the only 100% reliable method — avoids all string heuristics and package ordering issues.
        if !uniqueCandidates.isEmpty, Purchases.isConfigured {
            do {
                let storeProducts = try await Purchases.shared.products(uniqueCandidates)
                DebugLogService.shared.log("[SubscriptionManager] StoreKit products returned: \(storeProducts.map { "\($0.productIdentifier)=\(String(describing: $0.subscriptionPeriod?.unit.rawValue))" })")
                for product in storeProducts {
                    if let period = product.subscriptionPeriod {
                        switch period.unit {
                        case .month:
                            cachedTier = .proMonthly
                            DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (StoreKit period=month for \(product.productIdentifier))")
                            return
                        case .week:
                            cachedTier = .proWeekly
                            DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (StoreKit period=week for \(product.productIdentifier))")
                            return
                        default:
                            break
                        }
                    }
                }
            } catch {
                DebugLogService.shared.log("[SubscriptionManager] StoreKit products fetch failed: \(error.localizedDescription) — falling back to offering matching")
            }
        }

        let lowerCandidates = uniqueCandidates.map { $0.lowercased() }

        // FALLBACK 1: Match against offering packages by subscriptionPeriod (no string heuristics on package IDs)
        if let offering = currentOffering {
            for pkg in offering.availablePackages {
                let pkgProdId = pkg.storeProduct.productIdentifier.lowercased()
                DebugLogService.shared.log("[SubscriptionManager] Offering package: \(pkgProdId), type=\(pkg.packageType.rawValue), period=\(String(describing: pkg.storeProduct.subscriptionPeriod?.unit.rawValue))")
                if lowerCandidates.contains(pkgProdId) {
                    if pkg.packageType == .monthly || pkg.storeProduct.subscriptionPeriod?.unit == .month {
                        cachedTier = .proMonthly
                        DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (offering package period/type for \(pkgProdId))")
                        return
                    } else if pkg.packageType == .weekly || pkg.storeProduct.subscriptionPeriod?.unit == .week {
                        cachedTier = .proWeekly
                        DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (offering package period/type for \(pkgProdId))")
                        return
                    }
                }
            }
        }

        // FALLBACK 2: String heuristics on candidate product IDs
        for candidate in lowerCandidates {
            if candidate.contains("monthly") || candidate.contains("month") || candidate.contains("250") {
                cachedTier = .proMonthly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proMonthly (string heuristic: '\(candidate)')")
                return
            }
        }
        for candidate in lowerCandidates {
            if candidate.contains("weekly") || candidate.contains("week") {
                cachedTier = .proWeekly
                DebugLogService.shared.log("[SubscriptionManager] Resolved tier: proWeekly (string heuristic: '\(candidate)')")
                return
            }
        }

        // LAST RESORT: unknown billing period — log for diagnostics
        DebugLogService.shared.log("[SubscriptionManager] WARNING: Could not determine billing period. Candidates=\(uniqueCandidates). Check RevenueCat dashboard product IDs. Defaulting to proWeekly.")
        cachedTier = .proWeekly
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
            let customerInfo = try await Purchases.shared.customerInfo()
            self.activeCustomerInfo = customerInfo
            self.activeSubscriptions = customerInfo.activeSubscriptions
            let proEntitlement = customerInfo.entitlements["pro"]
            self.isPro = proEntitlement?.isActive ?? false
            self.activeProductIdentifier = proEntitlement?.productIdentifier ?? customerInfo.activeSubscriptions.first
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
