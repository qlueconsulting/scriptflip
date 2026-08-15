import SwiftUI
import RevenueCat
import RevenueCatUI

@MainActor
public struct PaywallContainerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var subscriptionManager: SubscriptionManager
    
    public init(subscriptionManager: SubscriptionManager? = nil) {
        _subscriptionManager = State(wrappedValue: subscriptionManager ?? SubscriptionManager.shared)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                
                #if canImport(RevenueCatUI)
                if Purchases.isConfigured, let offering = subscriptionManager.currentOffering {
                    PaywallView(offering: offering)
                        .onPurchaseCompleted { customerInfo in
                            if customerInfo.entitlements["pro"]?.isActive == true {
                                subscriptionManager.isPro = true
                                dismiss()
                            }
                        }
                        .onRestoreCompleted { customerInfo in
                            if customerInfo.entitlements["pro"]?.isActive == true {
                                subscriptionManager.isPro = true
                                dismiss()
                            }
                        }
                } else {
                    fallbackPaywallContent
                }
                #else
                fallbackPaywallContent
                #endif
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.gray)
                    }
                }
            }
            .task {
                if Purchases.isConfigured && subscriptionManager.currentOffering == nil {
                    await subscriptionManager.fetchOfferings()
                }
            }
        }
    }
    
    /// Fallback modern Paywall UI when RevenueCat offerings are loading, offline, or preview environment is active.
    private var fallbackPaywallContent: some View {
        VStack(spacing: 24) {
            Spacer()
            
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 64))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            VStack(spacing: 8) {
                Text("Unlock ScriptFlip Pro")
                    .font(.largeTitle.bold())
                    .foregroundStyle(.white)
                
                Text("Generate unlimited viral TikTok, Reels, and Shorts scripts with automated visual cues & teleprompter mode.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 24)
            }
            
            VStack(alignment: .leading, spacing: 14) {
                FeatureRow(icon: "infinite", title: "Unlimited Script Generations", subtitle: "No 3/month restrictions")
                FeatureRow(icon: "bolt.badge.clock.fill", title: "AI Timed Hooks (0-3s)", subtitle: "Maximize first 3 seconds retention")
                FeatureRow(icon: "eye.fill", title: "Full-Screen Teleprompter", subtitle: "Custom scroll speed & auto-mirroring")
                FeatureRow(icon: "square.and.arrow.up.fill", title: "Instant Export & Copy", subtitle: "Share directly to Notion, Notes, or team")
            }
            .padding(20)
            .background(Color.white.opacity(0.06))
            .cornerRadius(16)
            .padding(.horizontal, 20)
            
            if let errorMsg = subscriptionManager.errorMessage {
                Text(errorMsg)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
            }
            
            Spacer()
            
            VStack(spacing: 12) {
                Button(action: {
                    Task {
                        // If offering has packages, attempt real purchase; otherwise simulate
                        if let package = subscriptionManager.currentOffering?.availablePackages.first {
                            let success = await subscriptionManager.purchase(package: package)
                            if success { dismiss() }
                        } else {
                            subscriptionManager.isPro = true
                            dismiss()
                        }
                    }
                }) {
                    HStack {
                        if subscriptionManager.isPurchasing {
                            ProgressView()
                                .tint(.black)
                        } else {
                            Text(subscriptionManager.currentOffering?.availablePackages.first?.localizedPriceString.map { "Subscribe for \($0) / month" } ?? "Subscribe for $19.00 / month")
                                .font(.headline.bold())
                        }
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 54)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(14)
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
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let title: String
    let subtitle: String
    
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.cyan)
                .frame(width: 28)
            
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

#Preview {
    PaywallContainerView()
}
