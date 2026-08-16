import SwiftUI

/// Animated splash loading screen that transitions smoothly to the main UI.
public struct SplashScreenView<Content: View>: View {
    private let content: Content
    
    @State private var isSplashActive: Bool = true
    @State private var logoScale: CGFloat = 0.8
    @State private var logoOpacity: Double = 0.0
    @State private var textOpacity: Double = 0.0
    
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }
    
    public var body: some View {
        ZStack {
            if isSplashActive {
                splashScreen
                    .transition(.opacity.combined(with: .scale(scale: 1.05)))
            } else {
                content
                    .transition(.opacity)
            }
        }
        .onAppear {
            animateSplash()
        }
    }
    
    private var splashScreen: some View {
        ZStack {
            Color(red: 0.04, green: 0.04, blue: 0.06).ignoresSafeArea()
            
            VStack(spacing: 24) {
                Spacer()
                
                // Branded Logo Icon
                ZStack {
                    Circle()
                        .fill(
                            RadialGradient(
                                colors: [Color.cyan.opacity(0.35), Color.clear],
                                center: .center,
                                startRadius: 10,
                                endRadius: 90
                            )
                        )
                        .frame(width: 180, height: 180)
                    
                    RoundedRectangle(cornerRadius: 32)
                        .fill(
                            LinearGradient(
                                colors: [.cyan, .mint],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 104, height: 104)
                        .shadow(color: Color.cyan.opacity(0.5), radius: 24, y: 8)
                    
                    Image(systemName: "sparkles.tv.fill")
                        .font(.system(size: 52, weight: .bold))
                        .foregroundStyle(.black)
                }
                .scaleEffect(logoScale)
                .opacity(logoOpacity)
                
                // App Title & Tagline
                VStack(spacing: 8) {
                    Text("ScriptFlip")
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white, .white.opacity(0.9)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                    
                    Text("Viral Short-Form Scripts in Seconds")
                        .font(.subheadline.bold())
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.cyan, .mint],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .tracking(0.5)
                }
                .opacity(textOpacity)
                
                Spacer()
                
                // Subtle loading pulse indicator
                ProgressView()
                    .tint(.cyan)
                    .scaleEffect(0.9)
                    .opacity(textOpacity)
                    .padding(.bottom, 40)
            }
        }
    }
    
    private func animateSplash() {
        withAnimation(.easeOut(duration: 0.6)) {
            logoScale = 1.0
            logoOpacity = 1.0
        }
        
        withAnimation(.easeOut(duration: 0.7).delay(0.2)) {
            textOpacity = 1.0
        }
        
        // Transition to main content after smooth delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.4)) {
                isSplashActive = false
            }
        }
    }
}
