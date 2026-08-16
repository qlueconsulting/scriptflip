import SwiftUI

/// Main results view rendering the generated universal video script formatted as a vertical 9:16 preview.
public struct ScriptResultsView: View {
    public let scripts: [Script]
    public let onLaunchPrompter: (Script) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedIndex: Int = 0
    
    public init(scripts: [Script], onLaunchPrompter: @escaping (Script) -> Void) {
        self.scripts = scripts
        self.onLaunchPrompter = onLaunchPrompter
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Header summary
                        VStack(spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: "sparkles")
                                    .foregroundStyle(.cyan)
                                Text("Universal Script Ready")
                                    .font(.title3.bold())
                                    .foregroundStyle(.white)
                            }
                            
                            Text("Engineered for TikTok, Instagram Reels, and YouTube Shorts.")
                                .font(.caption)
                                .foregroundStyle(.gray)
                        }
                        .padding(.top, 12)
                        
                        if let firstScript = scripts.first {
                            ScriptCardView(script: firstScript, onLaunchPrompter: onLaunchPrompter)
                                .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 30)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                    .foregroundStyle(.cyan)
                    .font(.body.bold())
                }
            }
            .onAppear {
                // Automatically save generated scripts to history
                for script in scripts {
                    HistoryManager.shared.addScript(script)
                }
            }
        }
    }
}
