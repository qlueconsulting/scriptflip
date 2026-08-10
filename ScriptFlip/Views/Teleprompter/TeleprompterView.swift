import SwiftUI

/// High-contrast, full-screen Teleprompter view with scrolling text and controls.
public struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TeleprompterViewModel
    
    public init(script: Script) {
        _viewModel = State(initialValue: TeleprompterViewModel(script: script))
    }
    
    public var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            
            // Prompter Content
            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 32) {
                        // Title header
                        Text(viewModel.script.title.uppercased())
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(.yellow)
                            .padding(.bottom, 20)
                        
                        // Script sections formatted for prompter (Hook, Body, CTA)
                        ForEach(viewModel.script.sections) { section in
                            VStack(alignment: .leading, spacing: 12) {
                                HStack {
                                    Text(section.sectionType.rawValue.uppercased())
                                        .font(.system(size: 14, weight: .heavy, design: .monospaced))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(sectionColor(for: section.sectionType))
                                        .foregroundStyle(.black)
                                        .cornerRadius(6)
                                    
                                    Text(section.timeRange)
                                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                                        .foregroundStyle(.gray)
                                }
                                
                                Text(section.spokenText)
                                    .font(.system(size: viewModel.fontSize, weight: .bold, design: .rounded))
                                    .foregroundStyle(.white)
                                    .lineSpacing(10)
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "video.fill")
                                        .foregroundStyle(.cyan)
                                    Text("CUE: \(section.visualCue)")
                                        .font(.system(size: viewModel.fontSize * 0.55, weight: .medium))
                                        .foregroundStyle(.cyan)
                                        .italic()
                                }
                            }
                            .padding(.bottom, 16)
                        }
                        
                        // Bottom spacer to allow complete scroll past screen
                        Spacer(minLength: 500)
                    }
                    .padding(.horizontal, 28)
                    .padding(.top, 120)
                    .offset(y: -viewModel.scrollOffset)
                    .scaleEffect(x: viewModel.isMirrored ? -1 : 1, y: 1) // Mirror support for hardware prompters
                }
            }
            
            // Floating Reading Focus Guide Line
            VStack {
                Spacer()
                    .frame(height: 180)
                Rectangle()
                    .fill(Color.yellow.opacity(0.35))
                    .frame(height: 3)
                    .overlay(
                        HStack {
                            Image(systemName: "arrow.right.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                            Spacer()
                            Image(systemName: "arrow.left.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.yellow)
                        }
                        .padding(.horizontal, 12)
                    )
                Spacer()
            }
            .allowsHitTesting(false)
            
            // Top Header Overlay
            VStack {
                HStack {
                    Button(action: { dismiss() }) {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                            Text("Exit")
                        }
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Color.white.opacity(0.15))
                        .clipShape(Capsule())
                    }
                    
                    Spacer()
                    
                    Button(action: { viewModel.isMirrored.toggle() }) {
                        Image(systemName: "rectangle.2.swap")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(viewModel.isMirrored ? .yellow : .white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                    
                    Button(action: { viewModel.resetPrompter() }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.15))
                            .clipShape(Circle())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                
                Spacer()
            }
            
            // Bottom Control Toolbar
            VStack {
                Spacer()
                
                VStack(spacing: 16) {
                    HStack(spacing: 24) {
                        // Font size control
                        HStack(spacing: 8) {
                            Image(systemName: "textformat.size.smaller")
                                .foregroundStyle(.gray)
                            Slider(value: $viewModel.fontSize, in: 20...52, step: 2)
                                .tint(.cyan)
                            Image(systemName: "textformat.size.larger")
                                .foregroundStyle(.white)
                        }
                        .frame(width: 140)
                        
                        // Play / Pause main trigger
                        Button(action: { viewModel.togglePlayPause() }) {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 64, height: 64)
                                .background(viewModel.isPlaying ? Color.yellow : Color.cyan)
                                .clipShape(Circle())
                                .shadow(color: (viewModel.isPlaying ? Color.yellow : Color.cyan).opacity(0.5), radius: 10)
                        }
                        
                        // Speed control
                        HStack(spacing: 8) {
                            Image(systemName: "turtle.fill")
                                .foregroundStyle(.gray)
                            Slider(value: $viewModel.scrollSpeed, in: 10...100, step: 5)
                                .tint(.yellow)
                            Image(systemName: "hare.fill")
                                .foregroundStyle(.white)
                        }
                        .frame(width: 140)
                    }
                    
                    HStack {
                        Text("Speed: \(Int(viewModel.scrollSpeed)) px/s")
                        Spacer()
                        Text("Font: \(Int(viewModel.fontSize)) pt")
                    }
                    .font(.caption.monospaced())
                    .foregroundStyle(.gray)
                    .padding(.horizontal, 10)
                }
                .padding(20)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .statusBarHidden(true)
    }
    
    private func sectionColor(for type: ScriptSection.SectionType) -> Color {
        switch type {
        case .hook: return .yellow
        case .patternInterrupt: return .orange
        case .body: return .cyan
        case .callToAction: return .green
        }
    }
}
