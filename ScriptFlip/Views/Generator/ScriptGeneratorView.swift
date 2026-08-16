import SwiftUI

@MainActor
public struct ScriptGeneratorView: View {
    @State private var viewModel: ScriptGeneratorViewModel
    @State private var subscriptionManager: SubscriptionManager
    @State private var activePrompterScript: Script? = nil
    @State private var showErrorAlert: Bool = false
    
    public init(
        viewModel: ScriptGeneratorViewModel? = nil,
        subscriptionManager: SubscriptionManager? = nil
    ) {
        _viewModel = State(wrappedValue: viewModel ?? ScriptGeneratorViewModel())
        _subscriptionManager = State(wrappedValue: subscriptionManager ?? SubscriptionManager.shared)
    }
    
    public var body: some View {
        NavigationStack {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 28) {
                        // Top Header / Logo Banner
                        headerBanner
                        
                        // Input Type Selector Tabs
                        inputTypePicker
                        
                        // Main Text / URL Input Box
                        inputCard
                        
                        // Script Style Tone Selector
                        stylePickerSection
                        
                        // Error Alert Banner if applicable
                        if let error = viewModel.errorMessage {
                            HStack(spacing: 10) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.red)
                                Text(error)
                                    .font(.footnote)
                                    .foregroundStyle(.white)
                                Spacer()
                                Button(action: { viewModel.errorMessage = nil }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.gray)
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.15))
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.red.opacity(0.3), lineWidth: 1)
                            )
                        }
                        
                        // Generate Scripts CTA Button
                        generateButton
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
            }
            .navigationTitle("ScriptFlip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    usageBadge
                }
            }
            .alert("Script Generation Error", isPresented: $showErrorAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "An unexpected network error occurred.")
            }
            .onChange(of: viewModel.errorMessage) { oldValue, newValue in
                if newValue != nil {
                    showErrorAlert = true
                }
            }
            .sheet(isPresented: $viewModel.showResults) {
                ScriptResultsView(
                    scripts: viewModel.generatedScripts,
                    onLaunchPrompter: { script in
                        viewModel.showResults = false
                        activePrompterScript = script
                    }
                )
            }
            .sheet(isPresented: $viewModel.showPaywall) {
                PaywallContainerView()
            }
            .fullScreenCover(item: $activePrompterScript) { script in
                TeleprompterView(script: script)
            }
            .onAppear {
                viewModel.refreshUsage()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Turn Raw Content Into")
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                Text("Viral Scripts")
                    .font(.title2.bold())
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.cyan, .mint],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            
            Text("AI-optimized for TikTok, Reels, & Shorts with timed hooks (0–3s)")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }
    
    private var usageBadge: some View {
        Button(action: { viewModel.showPaywall = true }) {
            HStack(spacing: 6) {
                if subscriptionManager.isPro {
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    Text("PRO")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                } else {
                    Image(systemName: "sparkles")
                        .foregroundStyle(.cyan)
                    Text("\(viewModel.userUsage.remainingFreeGenerations) Free Left")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
        }
    }
    
    private var inputTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(ScriptGeneratorViewModel.InputMode.allCases) { mode in
                Button(action: { viewModel.inputMode = mode }) {
                    HStack(spacing: 6) {
                        Image(systemName: mode.iconName)
                        Text(mode.rawValue)
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(viewModel.inputMode == mode ? .black : .white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(viewModel.inputMode == mode ? Color.cyan : Color.white.opacity(0.08))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.inputMode == .url ? "Target Video / Podcast URL" : "Source Content / Transcript")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                Spacer()
                if !viewModel.inputText.isEmpty {
                    Button("Clear") {
                        viewModel.inputText = ""
                    }
                    .font(.caption)
                    .foregroundStyle(.cyan)
                }
            }
            
            if viewModel.inputMode == .url {
                TextField("https://youtube.com/watch?v=... or Podcast link", text: $viewModel.inputText)
                    .textFieldStyle(.plain)
                    .padding(14)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            } else {
                TextEditor(text: $viewModel.inputText)
                    .frame(height: 140)
                    .padding(8)
                    .scrollContentBackground(.hidden)
                    .background(Color.white.opacity(0.05))
                    .cornerRadius(12)
                    .foregroundStyle(.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }
        }
    }
    
    private var stylePickerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Script Tone & Style")
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            VStack(spacing: 10) {
                ForEach(ScriptStyle.allCases) { style in
                    Button(action: { viewModel.selectedStyle = style }) {
                        HStack(spacing: 12) {
                            Image(systemName: style.iconName)
                               .font(.title3)
                                .foregroundStyle(viewModel.selectedStyle == style ? .cyan : .gray)
                                .frame(width: 28)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(style.rawValue)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(.white)
                                Text(style.description)
                                    .font(.caption)
                                    .foregroundStyle(.gray)
                                    .multilineTextAlignment(.leading)
                            }
                            
                            Spacer()
                            
                            if viewModel.selectedStyle == style {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.cyan)
                            }
                        }
                        .padding(14)
                        .background(viewModel.selectedStyle == style ? Color.cyan.opacity(0.12) : Color.white.opacity(0.04))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(viewModel.selectedStyle == style ? Color.cyan : Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .cornerRadius(14)
                    }
                }
            }
        }
    }
    
    private var generateButton: some View {
        Button(action: {
            Task {
                do {
                    await viewModel.generateScripts()
                }
            }
        }) {
            HStack(spacing: 10) {
                if viewModel.isLoading {
                    ProgressView()
                        .tint(.black)
                    Text("Generating...")
                        .font(.headline.bold())
                } else {
                    Image(systemName: "sparkles")
                        .font(.title3.bold())
                    Text("Generate Short-Form Scripts")
                        .font(.headline.bold())
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: [.cyan, .mint],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.cyan.opacity(0.3), radius: 12, y: 4)
        }
        .disabled(viewModel.isLoading)
    }
}

#Preview {
    ScriptGeneratorView()
}
