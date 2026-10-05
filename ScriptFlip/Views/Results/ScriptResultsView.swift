import SwiftUI

/// Main results view featuring tabbed workflow: Transcript tab shown first by default,
/// followed by AI Generated Response tab with Teleprompter CTA positioned at the bottom.
public struct ScriptResultsView: View {
    public let scripts: [Script]
    public let onLaunchPrompter: (Script) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab: ResultsTab = .transcript
    @State private var isTranscriptCopied: Bool = false
    
    public enum ResultsTab: String, CaseIterable, Identifiable {
        case transcript = "Transcript"
        case aiScript = "AI Script"
        
        public var id: String { rawValue }
    }
    
    public init(scripts: [Script], onLaunchPrompter: @escaping (Script) -> Void) {
        self.scripts = scripts
        self.onLaunchPrompter = onLaunchPrompter
    }
    
    private var firstScript: Script? {
        scripts.first
    }
    
    private var transcriptText: String {
        guard let script = firstScript else { return "No transcript text available." }
        let text = script.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "No transcript text available." : text
    }
    
    private var badgeTitle: String {
        guard let script = firstScript else { return "Source Content" }
        switch script.transcriptType {
        case "whisper": return "AI Whisper Audio Transcription"
        case "closed_captions": return "Official Closed Captions"
        case "metadata": return "Post Metadata & Summary"
        default: return script.isTranscript ? "Video Source" : "User Input Notes"
        }
    }
    
    private var badgeColor: Color {
        guard let script = firstScript else { return .purple }
        switch script.transcriptType {
        case "whisper": return .cyan
        case "closed_captions": return .green
        case "metadata": return .orange
        default: return .purple
        }
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // Segmented Tab Picker: Transcript (Default 1st) & AI Script (2nd)
                    Picker("Results View", selection: $selectedTab) {
                        ForEach(ResultsTab.allCases) { tab in
                            Text(tab.rawValue).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    
                    ScrollView {
                        VStack(spacing: 16) {
                            switch selectedTab {
                            case .transcript:
                                transcriptView
                            case .aiScript:
                                if let script = firstScript {
                                    ScriptCardView(
                                        script: script,
                                        onLaunchPrompter: onLaunchPrompter,
                                        onSwitchToTranscript: { selectedTab = .transcript }
                                    )
                                    .padding(.horizontal, 16)
                                } else {
                                    Text("No script available.")
                                        .font(.subheadline)
                                        .foregroundStyle(.gray)
                                        .padding(.top, 40)
                                }
                            }
                        }
                        .padding(.bottom, 30)
                    }
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
                
                ToolbarItem(placement: .principal) {
                    Text(selectedTab == .transcript ? "Source Transcript" : "Generated Script")
                        .font(.headline)
                        .foregroundStyle(.white)
                }
            }
            .onAppear {
                for script in scripts {
                    HistoryManager.shared.addScript(script)
                }
            }
        }
    }
    
    // MARK: - Transcript Tab View (Displayed First by Default)
    @ViewBuilder
    private var transcriptView: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Badges row
            HStack(spacing: 8) {
                if let platform = firstScript?.platform, !platform.isEmpty {
                    Text(platform)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(6)
                }
                
                Text(badgeTitle)
                    .font(.caption.bold())
                    .foregroundStyle(badgeColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(badgeColor.opacity(0.15))
                    .cornerRadius(6)
                
                Spacer()
            }
            
            // Over-20-min / Metadata Notice
            if firstScript?.transcriptType == "metadata" {
                let isDurationExceeded = firstScript?.sourceText.contains("exceeds the 20-minute audio limit") ?? false
                let noticeText = isDurationExceeded
                    ? "Notice: Video duration exceeds the 20-minute audio limit. AI response generated from video metadata & summary."
                    : "Notice: Platform captions and direct audio extraction were unavailable for this video. AI response generated from video metadata & summary."
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(.orange)
                        .font(.body)
                    Text(noticeText)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.9))
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )
            }
            
            // Full Transcript Text Box
            VStack(alignment: .leading, spacing: 12) {
                Text(transcriptText)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.95))
                    .lineSpacing(6)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .background(Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .cornerRadius(14)
            
            // Action Buttons: Copy Transcript & Switch to Script Tab
            HStack(spacing: 12) {
                Button(action: {
                    UIPasteboard.general.string = transcriptText
                    isTranscriptCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                        isTranscriptCopied = false
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: isTranscriptCopied ? "checkmark" : "doc.on.doc")
                        Text(isTranscriptCopied ? "Copied!" : "Copy Transcript")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(isTranscriptCopied ? .green : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
                
                Button(action: { selectedTab = .aiScript }) {
                    HStack(spacing: 6) {
                        Text("View AI Script")
                        Image(systemName: "arrow.right")
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                }
            }
        }
        .padding(.horizontal, 16)
    }
}
