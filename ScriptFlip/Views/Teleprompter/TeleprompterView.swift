import SwiftUI

@MainActor
public struct TeleprompterView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: TeleprompterViewModel
    @State private var showControls: Bool = true
    @State private var controlsHideTask: Task<Void, Never>? = nil
    
    public init(script: Script) {
        _viewModel = State(initialValue: TeleprompterViewModel(script: script))
    }
    
    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                
                // Prompter Reading Content
                ScrollViewReader { _ in
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 28) {
                            // Title header
                            if !viewModel.script.title.isEmpty {
                                Text(viewModel.script.title)
                                    .font(.system(size: max(16, viewModel.fontSize * 0.6), weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .padding(.bottom, 8)
                            }
                            
                            // Pure spoken paragraphs (no stage directions, brackets, or timestamps)
                            Text(viewModel.script.cleanTeleprompterText)
                                .font(.system(size: viewModel.fontSize, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .lineSpacing(viewModel.fontSize * 0.42)
                                .multilineTextAlignment(.leading)
                                .frame(maxWidth: min(geometry.size.width - 56, 680), alignment: .leading)
                            
                            // Ample trailing bottom space to allow full reading to top of screen
                            Spacer(minLength: geometry.size.height * 0.75)
                        }
                        .padding(.horizontal, 28)
                        .padding(.top, geometry.size.height * 0.28)
                        .frame(maxWidth: .infinity)
                        .background(
                            GeometryReader { contentProxy in
                                Color.clear.preference(key: PrompterContentHeightKey.self, value: contentProxy.size.height)
                            }
                        )
                        .offset(y: -viewModel.scrollOffset)
                        .scaleEffect(x: viewModel.isMirrored ? -1 : 1, y: 1) // Mirror flip support for glass rigs
                    }
                    .onPreferenceChange(PrompterContentHeightKey.self) { height in
                        viewModel.contentHeight = Double(height)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    toggleControlsVisibility()
                }
                
                // Studio Edge Vignettes (Smooth reading focus zone)
                VStack {
                    LinearGradient(
                        colors: [Color.black, Color.black.opacity(0.85), Color.black.opacity(0)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.22)
                    .allowsHitTesting(false)
                    
                    Spacer()
                    
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.85), Color.black],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: geometry.size.height * 0.28)
                    .allowsHitTesting(false)
                }
                .ignoresSafeArea()
                
                // Reading Focus Guide Line with Arrows (Follows words as they scroll)
                VStack {
                    Spacer()
                        .frame(height: geometry.size.height * 0.32)
                    
                    ZStack {
                        // Soft highlight tint on active reading row
                        Rectangle()
                            .fill(Color.yellow.opacity(0.08))
                            .frame(height: viewModel.fontSize * 1.35)
                        
                        // Focus guide line with left and right indicator arrows
                        Rectangle()
                            .fill(Color.yellow.opacity(0.45))
                            .frame(height: 2.5)
                            .overlay(
                                HStack {
                                    Image(systemName: "arrow.right.fill")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(.yellow)
                                        .shadow(color: Color.yellow.opacity(0.6), radius: 4)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "arrow.left.fill")
                                        .font(.system(size: 13, weight: .black))
                                        .foregroundStyle(.yellow)
                                        .shadow(color: Color.yellow.opacity(0.6), radius: 4)
                                }
                                .padding(.horizontal, 14)
                            )
                    }
                    .frame(maxWidth: min(geometry.size.width - 24, 720))
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // Upper Left Clock Countdown Timer (Always visible so speaker tracks time remaining)
                VStack {
                    HStack {
                        HStack(spacing: 6) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.yellow)
                            
                            Text(viewModel.remainingTimeString)
                                .font(.system(size: 14, weight: .bold, design: .monospaced))
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(Color.yellow.opacity(0.4), lineWidth: 1)
                        )
                        .shadow(color: Color.black.opacity(0.6), radius: 6)
                        .scaleEffect(x: viewModel.isMirrored ? -1 : 1, y: 1) // Mirror flip support for glass rigs
                        
                        Spacer()
                    }
                    .padding(.leading, 20)
                    .padding(.top, showControls ? 64 : 18)
                    .animation(.easeInOut(duration: 0.2), value: showControls)
                    
                    Spacer()
                }
                .allowsHitTesting(false)
                
                // Top Header Overlay (Auto-hides during playback)
                if showControls {
                    VStack {
                        HStack {
                            Button(action: { dismiss() }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "chevron.left")
                                    Text("Done")
                                }
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 12) {
                                // Mirror Flip toggle
                                Button(action: { viewModel.isMirrored.toggle() }) {
                                    Image(systemName: "rectangle.2.swap")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(viewModel.isMirrored ? .yellow : .white)
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                                
                                // Rewind / Reset to Top
                                Button(action: { viewModel.resetPrompter() }) {
                                    Image(systemName: "arrow.counterclockwise")
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundStyle(.white)
                                        .padding(10)
                                        .background(.ultraThinMaterial)
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 14)
                        
                        Spacer()
                    }
                    .transition(.opacity)
                }
                
                // Sleek Floating Bottom Control Bar (Auto-hides during playback)
                if showControls {
                    VStack {
                        Spacer()
                        
                        HStack(alignment: .center, spacing: 18) {
                            // Left: Font Size Slider
                            VStack(spacing: 4) {
                                HStack {
                                    Image(systemName: "textformat")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.cyan)
                                    Text("Text")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.gray)
                                    Spacer()
                                    Text("\(Int(viewModel.fontSize))pt")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.cyan)
                                }
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "textformat.size.smaller")
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                    Slider(value: $viewModel.fontSize, in: 20...52, step: 2)
                                        .tint(.cyan)
                                    Image(systemName: "textformat.size.larger")
                                        .font(.caption)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            
                            // Center: Play / Pause Toggle Button
                            Button(action: {
                                viewModel.togglePlayPause()
                                if viewModel.isPlaying {
                                    scheduleControlsHide()
                                }
                            }) {
                                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                                    .font(.system(size: 24, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 56, height: 56)
                                    .background(viewModel.isPlaying ? Color.yellow : Color.cyan)
                                    .clipShape(Circle())
                                    .shadow(color: (viewModel.isPlaying ? Color.yellow : Color.cyan).opacity(0.4), radius: 10)
                            }
                            
                            // Right: Scroll Speed Slider
                            VStack(spacing: 4) {
                                HStack {
                                    Image(systemName: "gauge.with.needle.fill")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.yellow)
                                    Text("Speed")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.gray)
                                    Spacer()
                                    Text("\(Int(viewModel.scrollSpeed))")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.yellow)
                                }
                                
                                HStack(spacing: 6) {
                                    Image(systemName: "tortoise.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.gray)
                                    Slider(value: $viewModel.scrollSpeed, in: 10...100, step: 5)
                                        .tint(.yellow)
                                    Image(systemName: "hare.fill")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial)
                        .cornerRadius(22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 22)
                                .stroke(Color.white.opacity(0.12), lineWidth: 1)
                        )
                        .frame(maxWidth: min(geometry.size.width - 32, 600))
                        .padding(.bottom, 24)
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
            }
        }
        .statusBarHidden(!showControls)
        .onDisappear {
            controlsHideTask?.cancel()
        }
    }
    
    private func toggleControlsVisibility() {
        withAnimation(.easeInOut(duration: 0.25)) {
            showControls.toggle()
        }
        if showControls && viewModel.isPlaying {
            scheduleControlsHide()
        }
    }
    
    private func scheduleControlsHide() {
        controlsHideTask?.cancel()
        controlsHideTask = Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if !Task.isCancelled && viewModel.isPlaying {
                withAnimation(.easeInOut(duration: 0.35)) {
                    showControls = false
                }
            }
        }
    }
}

// MARK: - Content Height Preference Key

private struct PrompterContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
