import SwiftUI

/// Main results view rendering all generated video script options formatted as 9:16 vertical previews.
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
                Color.black.ignoresSafeArea()
                
                VStack(spacing: 16) {
                    // Header summary
                    VStack(spacing: 4) {
                        Text("Generated Scripts (9:16 Preview)")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                        
                        Text("Swipe horizontally or scroll to preview vertical short-form cards.")
                            .font(.caption)
                            .foregroundStyle(.gray)
                    }
                    .padding(.top, 12)
                    
                    // 9:16 Vertical Card Carousel / Paging View
                    TabView(selection: $selectedIndex) {
                        ForEach(Array(scripts.enumerated()), id: \.element.id) { index, script in
                            VStack {
                                ScriptCardView(script: script, onLaunchPrompter: onLaunchPrompter)
                                    .aspectRatio(9/16, contentMode: .fit)
                                    .padding(.horizontal, 8)
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(.page(indexDisplayMode: .always))
                    .indexViewStyle(.page(backgroundDisplayMode: .always))
                }
                .padding(.bottom, 20)
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
        }
    }
}
