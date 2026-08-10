import UIKit
import RevenueCat

/// Custom AppDelegate for initializing RevenueCat and App Services.
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Initialize RevenueCat SDK with API key loaded from AppEnvironment
        SubscriptionManager.configure(apiKey: AppEnvironment.revenueCatAPIKey)
        
        return true
    }
}
