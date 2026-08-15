import SwiftUI
import RevenueCat

@main
struct ScriptFlipApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Ensure RevenueCat SDK is configured safely before any view model initialization
        SubscriptionManager.configure(apiKey: AppEnvironment.revenueCatAPIKey)
    }
    
    var body: some Scene {
        WindowGroup {
            ScriptGeneratorView()
                .preferredColorScheme(.dark)
        }
    }
}
