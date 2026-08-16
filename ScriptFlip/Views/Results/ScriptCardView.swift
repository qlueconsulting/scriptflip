import SwiftUI

/// Component card displaying individual generated script with sections, cues, copy, save to history, and teleprompter launch.
public struct ScriptCardView: View {
    public let script: Script
    public let onLaunchPrompter: (Script) -> Void
    
    @State private var isCopied: Bool = false
    @State private var isSavedToHistory: Bool = false
    @State private var showShareSheet: Bool = false
    
    public init(script: Script, onLaunchPrompter: @escaping (Script) -> Void) {
        self.script = script
        self.onLaunchPrompter = onLaunchPrompter
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header: Title & Platform Badge
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Image(systemName: script.targetPlatform.iconName)
                            .foregroundStyle(.cyan)
                        Text(script.targetPlatform.rawValue)
                            .font(.caption.bold())
                            .foregroundStyle(.cyan)
                    }
                    
                    Text(script.title)
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                // Virality score pill
                VStack(spacing: 2) {
                    Text("\(script.viralityScore)%")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.green)
                    Text("Virality")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.gray)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.15))
                .cornerRadius(10)
            }
            
            Divider().background(Color.white.opacity(0.1))
            
            // Script Sections
            VStack(alignment: .leading, spacing: 16) {
                ForEach(script.sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(section.sectionType.rawValue)
                                .font(.caption2.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(badgeColor(for: section.sectionType).opacity(0.2))
                                .foregroundStyle(badgeColor(for: section.sectionType))
                                .cornerRadius(6)
                            
                            Text(section.timeRange)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.gray)
                        }
                        
                        Text(section.spokenText)
                            .font(.subheadline)
                            .foregroundStyle(.white)
                            .lineSpacing(4)
                        
                        HStack(spacing: 6) {
                            Image(systemName: "video.fill")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                            Text(section.visualCue)
                                .font(.caption)
                                .foregroundStyle(.gray)
                                .italic()
                        }
                        
                        if let audio = section.audioCue {
                            HStack(spacing: 6) {
                                Image(systemName: "speaker.wave.2.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                                Text(audio)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                            }
                        }
                    }
                }
            }
            
            // Key Takeaway Tip Box
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .foregroundStyle(.yellow)
                Text(script.keyTakeaway)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.yellow.opacity(0.1))
            .cornerRadius(10)
            
            // Actions Toolbar
            VStack(spacing: 10) {
                // Primary Launch Teleprompter Button
                Button(action: { onLaunchPrompter(script) }) {
                    HStack(spacing: 8) {
                        Image(systemName: "play.tv.fill")
                            .font(.headline)
                        Text("Open in Teleprompter")
                            .font(.headline.bold())
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .cornerRadius(12)
                    .shadow(color: Color.cyan.opacity(0.3), radius: 8, y: 3)
                }
                
                // Secondary Action Row: Copy, Save to History, Share
                HStack(spacing: 10) {
                    // Copy to Clipboard
                    Button(action: {
                        UIPasteboard.general.string = script.fullSpokenText
                        isCopied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                            isCopied = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            Text(isCopied ? "Copied!" : "Copy Script")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(isCopied ? .green : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(10)
                    }
                    
                    // Save to History Button
                    Button(action: {
                        HistoryManager.shared.addScript(script)
                        isSavedToHistory = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            isSavedToHistory = false
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: isSavedToHistory ? "checkmark.circle.fill" : "bookmark.fill")
                            Text(isSavedToHistory ? "Saved" : "Save")
                        }
                        .font(.subheadline.bold())
                        .foregroundStyle(isSavedToHistory ? .cyan : .white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 40)
                        .background(isSavedToHistory ? Color.cyan.opacity(0.15) : Color.white.opacity(0.08))
                        .cornerRadius(10)
                    }
                    
                    // Share Sheet
                    Button(action: { showShareSheet = true }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.subheadline.bold())
                            .foregroundStyle(.white)
                            .frame(width: 44, height: 40)
                            .background(Color.white.opacity(0.08))
                            .cornerRadius(10)
                    }
                }
            }
        }
        .padding(20)
        .background(Color.white.opacity(0.05))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .cornerRadius(20)
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [script.fullSpokenText])
        }
    }
    
    private func badgeColor(for type: ScriptSection.SectionType) -> Color {
        switch type {
        case .hook: return .yellow
        case .patternInterrupt: return .orange
        case .body: return .cyan
        case .callToAction: return .green
        }
    }
}

/// UIViewControllerRepresentable wrapper for native iOS UIActivityViewController share sheet.
public struct ShareSheet: UIViewControllerRepresentable {
    public let activityItems: [Any]
    public let applicationActivities: [UIActivity]?
    
    public init(activityItems: [Any], applicationActivities: [UIActivity]? = nil) {
        self.activityItems = activityItems
        self.applicationActivities = applicationActivities
    }
    
    public func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
        return controller
    }
    
    public func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

