import SwiftUI

@main
struct ScriptFlipApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            SplashScreenView {
                ScriptGeneratorView()
            }
            .preferredColorScheme(.dark)
        }
    }
}
