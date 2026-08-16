import UIKit

/// Custom AppDelegate ensuring 100% synchronous, pure launch lifecycle.
public class AppDelegate: NSObject, UIApplicationDelegate {
    public func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Zero eager SDK initializations or background tasks during application launch
        return true
    }
}
