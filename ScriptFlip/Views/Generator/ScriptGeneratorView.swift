import SwiftUI

@MainActor
public struct ScriptGeneratorView: View {
    @State private var viewModel: ScriptGeneratorViewModel
    @State private var subscriptionManager: SubscriptionManager
    @State private var activePrompterScript: Script? = nil
    
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
                        
                        // Target Response Duration Slider (1 to 5 Minutes)
                        durationSliderSection
                        
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
                ToolbarItemGroup(placement: .topBarLeading) {
                    HStack(spacing: 12) {
                        // History Button
                        Button(action: {
                            DebugLogService.shared.log("[View] History button tapped from toolbar.")
                            viewModel.showHistory = true
                        }) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.subheadline.bold())
                                .foregroundStyle(.cyan)
                        }
                        
                        // Diagnostics Button (Gated strictly behind DEBUG to prevent App Review rejection)
                        #if DEBUG
                        Button(action: { 
                            DebugLogService.shared.log("[View] Diagnostics button tapped from toolbar.")
                            viewModel.showDiagnostics = true 
                        }) {
                            Image(systemName: "wrench.and.screwdriver")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                        #endif
                        
                        // About App Button
                        Button(action: {
                            DebugLogService.shared.log("[View] About button tapped from toolbar.")
                            viewModel.showAbout = true
                        }) {
                            Image(systemName: "info.circle")
                                .font(.subheadline)
                                .foregroundStyle(.gray)
                        }
                    }
                }
                
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if subscriptionManager.activeTier == .free {
                        Button(action: {
                            DebugLogService.shared.log("[View] Manual Upgrade button tapped from toolbar.")
                            viewModel.showPaywall = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "crown.fill")
                                Text("Upgrade")
                            }
                            .font(.caption.bold())
                            .foregroundStyle(.black)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                LinearGradient(
                                    colors: [.yellow, .orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .cornerRadius(12)
                        }
                    }
                    
                    usageBadge
                }
            }
            .alert("Configuration Error", isPresented: $viewModel.showConfigAlert) {
                #if DEBUG
                Button("Open Diagnostics") {
                    viewModel.showDiagnostics = true
                }
                #endif
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.configurationAlertMessage ?? "Invalid Supabase URL or Anon Key.")
            }
            .alert("Script Generation Alert", isPresented: $viewModel.showErrorAlert) {
                #if DEBUG
                Button("Inspect Diagnostics") {
                    viewModel.showDiagnostics = true
                }
                #endif
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage ?? "An unexpected error occurred.")
            }
            .alert("No Captions Found", isPresented: $viewModel.showMissingCaptionsAlert) {
                Button("Switch to Raw Text") {
                    viewModel.inputMode = .rawText
                    viewModel.inputText = ""
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("No captions or transcripts were found for this video. Would you like to switch to 'Raw Transcript / Text' mode and paste the content manually?")
            }
            .sheet(isPresented: $viewModel.showResults) {
                ScriptResultsView(
                    scripts: viewModel.generatedScripts,
                    onLaunchPrompter: { script in
                        viewModel.showResults = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            activePrompterScript = script
                        }
                    }
                )
            }
            .sheet(isPresented: $viewModel.showHistory) {
                HistoryView { prompterScript in
                    viewModel.showHistory = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        activePrompterScript = prompterScript
                    }
                }
            }
            .sheet(isPresented: $viewModel.showAbout) {
                AboutView()
            }
            .sheet(isPresented: $viewModel.showPaywall, onDismiss: {
                Task {
                    await subscriptionManager.fetchCustomerInfo()
                    viewModel.refreshUsage()
                }
            }) {
                PaywallContainerView(subscriptionManager: subscriptionManager)
            }
            .sheet(isPresented: $viewModel.showDiagnostics) {
                NetworkDiagnosticsView(diagnostics: viewModel.getDiagnostics()) {
                    Task {
                        await viewModel.generateScripts()
                    }
                }
            }
            .fullScreenCover(item: $activePrompterScript) { script in
                TeleprompterView(script: script)
            }
            .onAppear {
                viewModel.refreshUsage()
            }
            .task {
                await subscriptionManager.fetchCustomerInfo()
                viewModel.refreshUsage()
            }
        }
    }
    
    // MARK: - Subviews
    
    private var headerBanner: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Turn Any Video Into")
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
            
            Text("AI-optimized 3–5 min spoken scripts for TikTok, Reels, Shorts & Podcasts")
                .font(.subheadline)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }
    
    private var usageBadge: some View {
        Button(action: { 
            DebugLogService.shared.log("[View] Usage badge tapped - presenting paywall & plan status.")
            viewModel.showPaywall = true 
        }) {
            HStack(spacing: 6) {
                switch subscriptionManager.activeTier {
                case .proWeekly:
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    Text("PRO (\(viewModel.userUsage.remainingProWeeklyGenerations)/50 Wk)")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                case .proMonthly:
                    Image(systemName: "crown.fill")
                        .foregroundStyle(.yellow)
                    Text("PRO (\(viewModel.userUsage.remainingProMonthlyGenerations)/250 Mo)")
                        .font(.caption.bold())
                        .foregroundStyle(.yellow)
                case .free:
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
        #if DEBUG
        .contextMenu {
            Section("DEBUG: Testing Controls") {
                Button("Reset Usage to 0") {
                    UsageTracker.shared.resetUsage()
                    SubscriptionManager.isTesterOverrideEnabled = false
                    viewModel.refreshUsage()
                }
                Button("Simulate: Free (3 uses)") {
                    UsageTracker.shared.resetUsage()
                    SubscriptionManager.isTesterOverrideEnabled = false
                    viewModel.refreshUsage()
                }
                Button("Simulate: Pro Weekly (50/wk)") {
                    UsageTracker.shared.resetUsage()
                    SubscriptionManager.isTesterOverrideEnabled = true
                    SubscriptionManager.testerOverrideTier = .proWeekly
                    viewModel.refreshUsage()
                }
                Button("Simulate: Pro Monthly (250/mo)") {
                    UsageTracker.shared.resetUsage()
                    SubscriptionManager.isTesterOverrideEnabled = true
                    SubscriptionManager.testerOverrideTier = .proMonthly
                    viewModel.refreshUsage()
                }
                Button("Exhaust Free Quota (use all 3)") {
                    var usage = UsageTracker.shared.getUsage()
                    // Directly write 3 uses via incrementing
                    UsageTracker.shared.resetUsage()
                    UsageTracker.shared.incrementUsage(tier: .free)
                    UsageTracker.shared.incrementUsage(tier: .free)
                    UsageTracker.shared.incrementUsage(tier: .free)
                    SubscriptionManager.isTesterOverrideEnabled = false
                    viewModel.refreshUsage()
                }
            }
        }
        #endif
    }

    
    private var inputTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(ScriptGeneratorViewModel.InputMode.allCases) { mode in
                Button(action: { 
                    DebugLogService.shared.log("[View] Switched input mode to \(mode.rawValue).")
                    viewModel.inputMode = mode 
                }) {
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
    
    private var usageCountString: String {
        switch subscriptionManager.activeTier {
        case .free:
            return "\(viewModel.userUsage.usedCount)/3"
        case .proWeekly:
            return "\(viewModel.userUsage.proUsedThisWeek)/50"
        case .proMonthly:
            return "\(viewModel.userUsage.proUsedThisMonth)/250"
        }
    }
    
    private var inputCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(viewModel.inputMode == .url ? "Target Video URL" : "Source Content / Transcript")
                    .font(.caption.bold())
                    .foregroundStyle(.gray)
                
                // Small Usage Box: response count / total available
                HStack(spacing: 4) {
                    Image(systemName: subscriptionManager.isProTierActive ? "crown.fill" : "sparkles")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(subscriptionManager.isProTierActive ? .yellow : .cyan)
                    Text(usageCountString)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color.white.opacity(0.12))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
                
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
                TextField("Paste TikTok, Instagram Reel, YouTube, or video URL...", text: $viewModel.inputText)
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
    
    private var durationSliderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.subheadline)
                        .foregroundStyle(.cyan)
                    Text("Response Length")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                }
                
                Spacer()
                
                Text("\(Int(viewModel.targetDurationMinutes)) min\(Int(viewModel.targetDurationMinutes) > 1 ? "s" : "")")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(.cyan)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.cyan.opacity(0.12))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.cyan.opacity(0.25), lineWidth: 1)
                    )
            }
            
            HStack(spacing: 12) {
                Text("1 min")
                    .font(.caption2.bold())
                    .foregroundStyle(.gray)
                
                Slider(value: $viewModel.targetDurationMinutes, in: 1...5, step: 1)
                    .tint(.cyan)
                
                Text("5 mins")
                    .font(.caption2.bold())
                    .foregroundStyle(.gray)
            }
            .padding(.horizontal, 4)
        }
        .padding(14)
        .background(Color.white.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }
    
    private var stylePickerSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Script Tone & Style")
                .font(.headline.bold())
                .foregroundStyle(.white)
            
            VStack(spacing: 10) {
                ForEach(ScriptStyle.allCases) { style in
                    Button(action: { 
                        DebugLogService.shared.log("[View] Selected script style: \(style.rawValue).")
                        viewModel.selectedStyle = style 
                    }) {
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
        VStack(spacing: 12) {
            Button(action: {
                DebugLogService.shared.log("[View] Generate button tapped.")
                Task {
                    await viewModel.generateScripts()
                }
            }) {
                HStack(spacing: 10) {
                    if viewModel.isLoading {
                        ProgressView()
                            .tint(.black)
                        Text(viewModel.loadingPhaseText)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    } else {
                        Image(systemName: "sparkles")
                            .font(.title3.bold())
                        Text("Generate AI Response")
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
            
            // Interactive Progress Indicator & Timer during AI generation
            if viewModel.isLoading {
                VStack(spacing: 6) {
                    ProgressView(value: viewModel.loadingProgress, total: 1.0)
                        .progressViewStyle(.linear)
                        .tint(.cyan)
                        .scaleEffect(x: 1, y: 1.5, anchor: .center)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                    
                    HStack {
                        Text("Crafting \(Int(viewModel.targetDurationMinutes)) min spoken script...")
                            .font(.caption2)
                            .foregroundStyle(.gray)
                        Spacer()
                        Text("\(viewModel.elapsedSeconds)s elapsed")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.cyan)
                    }
                }
                .padding(.horizontal, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isLoading)
    }
}

#Preview {
    ScriptGeneratorView()
}
