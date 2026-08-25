import SwiftUI

/// About and App Information screen displaying version, developer info, and policy links.
public struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    
    public init() {}
    
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
    
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        // App Icon & Header
                        VStack(spacing: 14) {
                            Image("ScriptFlipLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: 240, maxHeight: 110)
                                .shadow(color: Color.cyan.opacity(0.35), radius: 16, y: 4)
                            
                            VStack(spacing: 4) {
                                Text("Version \(appVersion) (Build \(buildNumber))")
                                    .font(.footnote.monospaced())
                                    .foregroundStyle(.gray)
                            }
                        }
                        .padding(.top, 20)
                        
                        // App Mission Card
                        VStack(alignment: .leading, spacing: 10) {
                            Text("About ScriptFlip")
                                .font(.headline.bold())
                                .foregroundStyle(.white)
                            
                            Text("ScriptFlip turns long YouTube videos, podcasts, and raw transcripts into high-retention, teleprompter-ready short-form scripts engineered for TikTok, Instagram Reels, and YouTube Shorts.")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                                .lineSpacing(4)
                        }
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        
                        // Developer & Legal Links
                        VStack(spacing: 1) {
                            aboutRow(
                                title: "Developer",
                                value: "Qlue Consulting Inc.",
                                icon: "building.2.fill"
                            )
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            aboutLinkRow(
                                title: "Privacy Policy",
                                icon: "hand.raised.fill",
                                url: "https://qlueconsulting.com/privacy"
                            )
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            aboutLinkRow(
                                title: "Terms of Service",
                                icon: "doc.text.fill",
                                url: "https://qlueconsulting.com/terms"
                            )
                            
                            Divider().background(Color.white.opacity(0.08))
                            
                            aboutRow(
                                title: "AI Intelligence",
                                value: "Claude 3.5 Sonnet / Haiku",
                                icon: "cpu.fill"
                            )
                        }
                        .background(Color.white.opacity(0.05))
                        .cornerRadius(16)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        
                        // Copyright Footer
                        Text("© 2026 Qlue Consulting Inc. All rights reserved.")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                            .padding(.top, 10)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 30)
                }
            }
            .navigationTitle("About")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .font(.body.bold())
                    .foregroundStyle(.cyan)
                }
            }
        }
    }
    
    private func aboutRow(title: String, value: String, icon: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(.cyan)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.white)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(.gray)
        }
        .padding(16)
    }
    
    private func aboutLinkRow(title: String, icon: String, url: String) -> some View {
        Link(destination: URL(string: url) ?? URL(string: "https://qlueconsulting.com")!) {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.cyan)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
            }
            .padding(16)
        }
    }
}
