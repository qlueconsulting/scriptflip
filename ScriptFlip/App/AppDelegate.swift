import UIKit

/// Custom AppDelegate ensuring clean launch lifecycle.
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Configure RevenueCat and check subscription entitlement at launch so app reflects paid access
        SubscriptionManager.ensureConfigured()
        Task {
            await SubscriptionManager.shared.fetchCustomerInfo()
        }
        return true
    }
}
