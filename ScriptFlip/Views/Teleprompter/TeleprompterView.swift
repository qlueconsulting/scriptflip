import SwiftUI

@MainActor
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
                                        .font(.system(size: max(12, viewModel.fontSize * 0.55), weight: .medium))
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
            
            // Bottom Control Toolbar - Fixed slider layout alignment & direct label pairing
            VStack {
                Spacer()
                
                VStack(spacing: 16) {
                    HStack(alignment: .center, spacing: 16) {
                        // Left Column: Font Size Control with its own direct label
                        VStack(spacing: 6) {
                            HStack {
                                Image(systemName: "textformat")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.cyan)
                                Text("Text Size")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(Int(viewModel.fontSize)) pt")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.cyan)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "textformat.size.smaller")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.gray)
                                Slider(value: $viewModel.fontSize, in: 20...52, step: 2)
                                    .tint(.cyan)
                                Image(systemName: "textformat.size.larger")
                                    .font(.system(size: 15, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        // Center Column: Big Play / Pause main trigger button
                        Button(action: { viewModel.togglePlayPause() }) {
                            Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 26, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 60, height: 60)
                                .background(viewModel.isPlaying ? Color.yellow : Color.cyan)
                                .clipShape(Circle())
                                .shadow(color: (viewModel.isPlaying ? Color.yellow : Color.cyan).opacity(0.5), radius: 10)
                        }
                        
                        // Right Column: Scroll Speed Control with its own direct label
                        VStack(spacing: 6) {
                            HStack {
                                Image(systemName: "gauge.with.needle.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.yellow)
                                Text("Scroll Speed")
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                Spacer()
                                Text("\(Int(viewModel.scrollSpeed)) px/s")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.yellow)
                            }
                            
                            HStack(spacing: 6) {
                                Image(systemName: "tortoise.fill")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.gray)
                                Slider(value: $viewModel.scrollSpeed, in: 10...100, step: 5)
                                    .tint(.yellow)
                                Image(systemName: "hare.fill")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(18)
                .background(.ultraThinMaterial)
                .cornerRadius(24)
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
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
