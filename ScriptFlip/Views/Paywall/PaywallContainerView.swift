import SwiftUI
import RevenueCat

@MainActor
public struct PaywallContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionManager: SubscriptionManager
    @State private var selectedPackageType: SelectedTier = .monthly
    
    public enum SelectedTier {
        case weekly
        case monthly
    }
    
    public init(subscriptionManager: SubscriptionManager? = nil) {
        _subscriptionManager = State(wrappedValue: subscriptionManager ?? SubscriptionManager.shared)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 24) {
                        // Header Branding
                        VStack(spacing: 12) {
                            Image("ScriptFlipLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 220, maxHeight: 90)
                                .shadow(color: Color.cyan.opacity(0.35), radius: 16, y: 4)
                            
                            VStack(spacing: 6) {
                                Text(headerTitle)
                                    .font(.title.bold())
                                    .foregroundStyle(.white)
                                    .multilineTextAlignment(.center)
                                
                                Text(headerSubtitle)
                                    .font(.subheadline)
                                    .foregroundStyle(.gray)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                        }
                        .padding(.top, 16)
                        
                        // Feature highlights
                        VStack(alignment: .leading, spacing: 14) {
                            FeatureRow(icon: "sparkles", title: "AI Speaking Scripts (3-5 Mins)", subtitle: "Rich, detailed monologues formatted for seamless speech")
                            FeatureRow(icon: "play.tv.fill", title: "Distraction-Free Teleprompter", subtitle: "Clean studio display with smooth autoscroll & mirror flip")
                            FeatureRow(icon: "video.fill", title: "Universal Video Link Support", subtitle: "Turn TikTok, Instagram Reels, Facebook & YouTube into scripts")
                            FeatureRow(icon: "square.and.arrow.up", title: "Instant Share & Copy", subtitle: "Direct export to Notes, Notion, or teleprompter glass rigs")
                        }
                        .padding(18)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(18)
                        .padding(.horizontal, 20)
                        
                        // Upgrade Tiers / Packages (STRICT UPGRADE-ONLY: NO DOWNGRADES)
                        tierSelectionSection
                            .padding(.horizontal, 20)
                        
                        if let errorMsg = subscriptionManager.errorMessage {
                            Text(errorMsg)
                                .font(.caption)
                                .foregroundStyle(.red)
                                .padding(.horizontal, 20)
                                .multilineTextAlignment(.center)
                        }
                        
                        // Purchase Button
                        purchaseActionSection
                            .padding(.horizontal, 20)
                        
                        // Statutory App Store Disclosures & Legal Links
                        legalFooter
                            .padding(.horizontal, 20)
                            .padding(.bottom, 24)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .task {
                await subscriptionManager.fetchOfferings()
            }
        }
    }
    
    // MARK: - Dynamic Headers based on Current Tier
    
    private var headerTitle: String {
        switch subscriptionManager.activeTier {
        case .free:
            return "Upgrade to ScriptFlip Pro"
        case .proWeekly:
            return "Upgrade to Pro Monthly"
        case .proMonthly:
            return "You're on Pro Monthly"
        }
    }
    
    private var headerSubtitle: String {
        switch subscriptionManager.activeTier {
        case .free:
            return "Choose Weekly or Monthly access to generate viral 3-5 minute scripts."
        case .proWeekly:
            return "Upgrade from Weekly (50/wk) to Monthly (250/mo) for 5x more generations."
        case .proMonthly:
            return "You have unlocked the highest tier with 250 scripts every month."
        }
    }
    
    // MARK: - Upgrade-Only Tier Selection
    
    @ViewBuilder
    private var tierSelectionSection: some View {
        switch subscriptionManager.activeTier {
        case .free:
            // Free user: Show both Weekly and Monthly
            VStack(spacing: 12) {
                tierCard(
                    tier: .monthly,
                    title: "Pro Monthly",
                    quota: "250 scripts / month",
                    price: monthlyPriceString,
                    badge: "BEST VALUE",
                    isSelected: selectedPackageType == .monthly
                )
                
                tierCard(
                    tier: .weekly,
                    title: "Pro Weekly",
                    quota: "50 scripts / week",
                    price: weeklyPriceString,
                    badge: nil,
                    isSelected: selectedPackageType == .weekly
                )
            }
            
        case .proWeekly:
            // Pro Weekly user: ONLY SHOW MONTHLY UPGRADE (no downgrade to weekly or free)
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Current Plan: Pro Weekly (50/week)")
                        .font(.caption.bold())
                        .foregroundStyle(.gray)
                    Spacer()
                }
                .padding(.horizontal, 4)
                
                tierCard(
                    tier: .monthly,
                    title: "Upgrade to Pro Monthly",
                    quota: "250 scripts / month (5x more scripts)",
                    price: monthlyPriceString,
                    badge: "RECOMMENDED UPGRADE",
                    isSelected: true
                )
            }
            
        case .proMonthly:
            // Pro Monthly user: Already at top tier
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "crown.fill")
                        .font(.title2)
                        .foregroundStyle(.yellow)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Active Tier: Pro Monthly")
                            .font(.headline.bold())
                            .foregroundStyle(.white)
                        Text("250 scripts / month quota is active.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.yellow.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.yellow.opacity(0.3), lineWidth: 1)
                )
                .cornerRadius(14)
                
                Link(destination: URL(string: "https://apps.apple.com/account/subscriptions")!) {
                    HStack {
                        Text("Manage Subscription in Apple ID Settings")
                            .font(.subheadline.bold())
                        Image(systemName: "arrow.up.right")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.cyan)
                    .padding(.vertical, 4)
                }
            }
        }
    }
    
    private func tierCard(
        tier: SelectedTier,
        title: String,
        quota: String,
        price: String,
        badge: String?,
        isSelected: Bool
    ) -> some View {
        Button(action: {
            selectedPackageType = tier
        }) {
            HStack(spacing: 14) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .cyan : .gray)
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 9, weight: .black))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.cyan)
                                .foregroundStyle(.black)
                                .cornerRadius(4)
                        }
                    }
                    
                    Text(quota)
                        .font(.caption)
                        .foregroundStyle(.gray)
                }
                
                Spacer()
                
                Text(price)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
            }
            .padding(16)
            .background(isSelected ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.cyan : Color.white.opacity(0.08), lineWidth: isSelected ? 1.5 : 1)
            )
            .cornerRadius(14)
        }
    }
    
    // MARK: - Purchase Actions
    
    @ViewBuilder
    private var purchaseActionSection: some View {
        if subscriptionManager.activeTier != .proMonthly {
            VStack(spacing: 12) {
                Button(action: {
                    executePurchase()
                }) {
                    HStack(spacing: 8) {
                        if subscriptionManager.isPurchasing {
                            ProgressView()
                                .tint(.black)
                            Text("Processing with Apple...")
                                .font(.headline.bold())
                        } else {
                            Text(ctaButtonTitle)
                                .font(.headline.bold())
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
                    .shadow(color: Color.cyan.opacity(0.3), radius: 10, y: 3)
                }
                .disabled(subscriptionManager.isPurchasing)
                
                Button(action: {
                    Task {
                        let success = await subscriptionManager.restorePurchases()
                        if success {
                            dismiss()
                        }
                    }
                }) {
                    Text("Restore Purchases")
                        .font(.footnote)
                        .foregroundStyle(.gray)
                }
                .disabled(subscriptionManager.isPurchasing)
            }
        }
    }
    
    private var ctaButtonTitle: String {
        switch subscriptionManager.activeTier {
        case .free:
            return selectedPackageType == .monthly ? "Subscribe Monthly for \(monthlyPriceString)" : "Subscribe Weekly for \(weeklyPriceString)"
        case .proWeekly:
            return "Upgrade to Monthly for \(monthlyPriceString)"
        case .proMonthly:
            return "Subscribed"
        }
    }
    
    private var monthlyPriceString: String {
        if let pkg = subscriptionManager.currentOffering?.availablePackages.first(where: {
            $0.storeProduct.productIdentifier.lowercased().contains("month")
        }) {
            return "\(pkg.localizedPriceString) / month"
        }
        return "$19.99 / month"
    }
    
    private var weeklyPriceString: String {
        if let pkg = subscriptionManager.currentOffering?.availablePackages.first(where: {
            $0.storeProduct.productIdentifier.lowercased().contains("week")
        }) {
            return "\(pkg.localizedPriceString) / week"
        }
        return "$4.99 / week"
    }
    
    private func executePurchase() {
        let isMonthly = (subscriptionManager.activeTier == .proWeekly) || (selectedPackageType == .monthly)
        
        Task {
            // If offerings haven't loaded yet, try one more fetch with user feedback
            if subscriptionManager.currentOffering == nil {
                await subscriptionManager.fetchOfferings()
            }
            
            let matchingPackage = subscriptionManager.currentOffering?.availablePackages.first(where: { pkg in
                let id = pkg.storeProduct.productIdentifier.lowercased()
                return isMonthly ? (id.contains("monthly") || id.contains("month")) : (id.contains("weekly") || id.contains("week"))
            }) ?? subscriptionManager.currentOffering?.availablePackages.first
            
            guard let pkg = matchingPackage else {
                // Surface a clear error rather than silently failing
                subscriptionManager.errorMessage = "Could not load subscription options from the App Store. Please check your internet connection and try again. If the issue persists, verify that in-app purchases are configured in RevenueCat and App Store Connect."
                return
            }
            
            let success = await subscriptionManager.purchase(package: pkg)
            if success {
                dismiss()
            }
        }
    }
    
    // MARK: - Legal Footer
    
    private var legalFooter: some View {
        VStack(spacing: 8) {
            Text("Subscription auto-renews unless canceled in Apple ID Settings at least 24 hours before the end of the current billing period.")
                .font(.caption2)
                .foregroundStyle(.gray.opacity(0.8))
                .multilineTextAlignment(.center)
            
            HStack(spacing: 16) {
                Link("Privacy Policy", destination: URL(string: "https://gist.github.com/qlueconsulting/dd318693733c41c5a20ae5e39d585985")!)
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
                
                Text("•").foregroundStyle(.gray)
                
                Link("Terms of Use (EULA)", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
                
                Text("•").foregroundStyle(.gray)
                
                Link("Support", destination: URL(string: "https://gist.github.com/qlueconsulting/1b038663d0ea21b8ccda1623b7e67f97")!)
                    .font(.caption2.bold())
                    .foregroundStyle(.cyan)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 26)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(.white)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.gray)
            }
        }
    }
}
