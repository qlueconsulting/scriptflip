import SwiftUI

/// Modern modal sheet displaying extracted video transcript or source user text
public struct TranscriptSheetView: View {
    public let script: Script
    @Environment(\.dismiss) private var dismiss
    @State private var isCopied: Bool = false
    
    public init(script: Script) {
        self.script = script
    }
    
    private var transcriptText: String {
        script.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "No transcript text available."
            : script.sourceText
    }
    
    private var badgeTitle: String {
        switch script.transcriptType {
        case "whisper": return "AI Whisper Audio Transcription"
        case "closed_captions": return "Official Closed Captions"
        case "metadata": return "Post Metadata & Summary"
        default: return script.isTranscript ? "Video Source" : "User Input Notes"
        }
    }
    
    private var badgeColor: Color {
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
                
                VStack(alignment: .leading, spacing: 16) {
                    // Header badges
                    HStack(spacing: 8) {
                        if let platform = script.platform, !platform.isEmpty {
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
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    
                    // Scrollable Selection Card
                    ScrollView {
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
                        .padding(.horizontal, 20)
                    }
                    
                    // Bottom Action Bar
                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = transcriptText
                            isCopied = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                                isCopied = false
                            }
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                                Text(isCopied ? "Copied!" : "Copy Transcript")
                            }
                            .font(.subheadline.bold())
                            .foregroundStyle(isCopied ? .green : .white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(12)
                        }
                        
                        Button(action: { dismiss() }) {
                            Text("Back to Script")
                                .font(.subheadline.bold())
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .background(Color.purple)
                                .cornerRadius(12)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .navigationTitle(script.isTranscript ? "Video Transcript" : "Source Input & Transcript")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.body)
                            .foregroundStyle(.gray)
                    }
                }
            }
        }
    }
}
