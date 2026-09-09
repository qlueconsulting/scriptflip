import UIKit

/// Custom AppDelegate ensuring clean launch lifecycle.
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure RevenueCat and pre-fetch offerings at launch so StoreKit packages are ready before paywall opens
        SubscriptionManager.ensureConfigured()
        Task {
            await SubscriptionManager.shared.fetchOfferings()
        }
        return true
    }
}
