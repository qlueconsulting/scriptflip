import Foundation
import Observation

/// Main view model powering `ScriptGeneratorView`.
@Observable
@MainActor
public final class ScriptGeneratorViewModel {
    public var inputMode: InputMode = .url
    public var inputText: String = ""
    public var selectedStyle: ScriptStyle = .casual
    public var targetDurationMinutes: Double = 3.0 // 1 to 5 minutes duration slider
    
    public var isLoading: Bool = false
    public var loadingPhaseText: String = "Connecting to AI..."
    public var loadingProgress: Double = 0.0
    public var elapsedSeconds: Int = 0
    private var progressTask: Task<Void, Never>? = nil
    
    public var errorMessage: String? = nil
    public var showErrorAlert: Bool = false
    public var configurationAlertMessage: String? = nil
    public var showConfigAlert: Bool = false
    public var showMissingCaptionsAlert: Bool = false
    
    public var generatedScripts: [Script] = []
    
    public var showPaywall: Bool = false {
        didSet {
            if showPaywall && subscriptionManager.activeTier == .proMonthly {
                showPaywall = false
            }
        }
    }
    public var showResults: Bool = false
    public var showDiagnostics: Bool = false
    public var showHistory: Bool = false
    public var showAbout: Bool = false
    
    public var usageRevision: Int = 0
    public var userUsage: UserUsage {
        _ = usageRevision
        return usageTracker.getUsage()
    }
    
    private let apiService: ScriptAPIServiceProtocol
    private let usageTracker: UsageTracker
    public let subscriptionManager: SubscriptionManager
    
    public enum InputMode: String, CaseIterable, Identifiable, Sendable {
        case url = "Video Link"
        case rawText = "Raw Transcript / Text"
        
        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .url: return "play.rectangle.fill"
            case .rawText: return "doc.text.fill"
            }
        }
    }

    public init(
        apiService: ScriptAPIServiceProtocol = ScriptAPIService(),
        usageTracker: UsageTracker = UsageTracker.shared,
        subscriptionManager: SubscriptionManager? = nil
    ) {
        self.apiService = apiService
        self.usageTracker = usageTracker
        self.subscriptionManager = subscriptionManager ?? SubscriptionManager.shared
        // Zero eager disk I/O or background operations in init
    }
    
    public func refreshUsage() {
        self.usageRevision += 1
        let current = userUsage
        let tier = subscriptionManager.activeTier
        switch tier {
        case .proWeekly:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (PRO WEEKLY): \(current.proUsedThisWeek)/50 weekly (\(current.remainingProWeeklyGenerations) left).")
        case .proMonthly:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (PRO MONTHLY): \(current.proUsedThisMonth)/250 monthly (\(current.remainingProMonthlyGenerations) left).")
        case .free:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (FREE): \(current.usedCount)/3 used (\(current.remainingFreeGenerations) remaining).")
        }
    }
    
    public func getDiagnostics() -> NetworkDiagnosticInfo {
        apiService.getDiagnostics()
    }
    
    public var canGenerateFree: Bool {
        !userUsage.isLimitReached(for: subscriptionManager.activeTier)
    }
    
    public func generateScripts() async {
        DebugLogService.shared.log("[ViewModel] generateScripts invoked. inputMode=\(inputMode.rawValue), textLength=\(inputText.count)")
        
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            let msg = "Please enter a valid video link (TikTok, Reels, YouTube) or transcript text."
            DebugLogService.shared.log("[ViewModel] Blocked early: \(msg)")
            self.errorMessage = msg
            self.showErrorAlert = true
            return
        }
        
        refreshUsage()
        
        let activeTier = subscriptionManager.activeTier
        
        // 1. Quota Verification per Tier
        switch activeTier {
        case .proWeekly:
            if userUsage.isProWeeklyLimitReached {
                let limitMsg = "Weekly Pro Limit Reached: You have used your 50 script generations for this week. Your weekly quota will automatically reset next week."
                DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                self.errorMessage = limitMsg
                self.showErrorAlert = true
                return
            }
            DebugLogService.shared.log("[ViewModel] Pro Weekly active: \(userUsage.remainingProWeeklyGenerations)/50 scripts left.")
            
        case .proMonthly:
            if userUsage.isProMonthlyLimitReached {
                let limitMsg = "Monthly Pro Limit Reached: You have used your 250 script generations for this month. Your monthly quota will reset next month."
                DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                self.errorMessage = limitMsg
                self.showErrorAlert = true
                return
            }
            DebugLogService.shared.log("[ViewModel] Pro Monthly active: \(userUsage.remainingProMonthlyGenerations)/250 scripts left.")
            
        case .free:
            if userUsage.isLimitReached {
                DebugLogService.shared.log("[ViewModel] Free quota reached. Checking live Pro subscription status...")
                let hasLivePro = await subscriptionManager.fetchCustomerInfo()
                
                if !hasLivePro {
                    let limitMsg = "Subscription required: You have used your 3 free generations for this month. Upgrade to Pro Weekly (50/wk) or Pro Monthly (250/mo)."
                    DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                    self.errorMessage = limitMsg
                    self.showPaywall = true
                    // Do not set showErrorAlert = true simultaneously to avoid modal presentation collision on iPad
                    return
                }
            }
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.showErrorAlert = false
        startProgressTracking()
        defer {
            self.isLoading = false
            stopProgressTracking()
        }
        
        let requestType: GenerationRequest.InputType = (inputMode == .url)
            ? .videoUrl
            : .rawText
            
        let payload = GenerationRequest(
            inputText: trimmedInput,
            scriptStyle: selectedStyle.rawValue,
            inputType: requestType,
            outputCount: 1,
            targetDurationMinutes: Int(targetDurationMinutes),
            anonymousUserId: KeychainService.shared.anonymousUserId,
            clientTier: activeTier.rawValue
        )
        
        DebugLogService.shared.log("[ViewModel] Dispatching request to APIService for style '\(selectedStyle.rawValue)'...")
        
        do {
            let scripts = try await apiService.generateScripts(request: payload)
            DebugLogService.shared.log("[ViewModel] Successfully received \(scripts.count) scripts from Edge Function.")
            self.generatedScripts = scripts
            
            // Auto-save generated scripts to history
            for script in scripts {
                HistoryManager.shared.addScript(script)
            }
            
            // Increment usage count for active tier
            usageTracker.incrementUsage(tier: subscriptionManager.activeTier)
            self.usageRevision += 1
            let currentUsage = self.userUsage
            switch subscriptionManager.activeTier {
            case .proWeekly:
                DebugLogService.shared.log("[ViewModel] Incremented Pro Weekly usage: \(currentUsage.proUsedThisWeek)/50.")
            case .proMonthly:
                DebugLogService.shared.log("[ViewModel] Incremented Pro Monthly usage: \(currentUsage.proUsedThisMonth)/250.")
            case .free:
                DebugLogService.shared.log("[ViewModel] Incremented Free usage: \(currentUsage.usedCount)/3.")
            }
            
            self.showResults = true
        } catch let apiError as ScriptAPIError {
            DebugLogService.shared.log("[ViewModel] ScriptAPIError caught: \(apiError.localizedDescription)")
            
            switch apiError {
            case .configurationError(let message):
                self.configurationAlertMessage = "Configuration Error: Invalid Supabase URL or Anon Key.\n\n\(message)"
                self.showConfigAlert = true
                self.errorMessage = self.configurationAlertMessage
            default:
                let desc = apiError.localizedDescription
                self.errorMessage = desc
                if desc.localizedCaseInsensitiveContains("captions") || desc.localizedCaseInsensitiveContains("transcript") {
                    self.showMissingCaptionsAlert = true
                } else {
                    self.showErrorAlert = true
                }
            }
        } catch {
            DebugLogService.shared.log("[ViewModel] Unexpected error caught: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
    
    // MARK: - Dynamic Progress Tracking
    
    private func startProgressTracking() {
        elapsedSeconds = 0
        loadingProgress = 0.05
        loadingPhaseText = (inputMode == .url) ? "Analyzing video source..." : "Processing source text..."
        
        progressTask?.cancel()
        progressTask = Task { @MainActor [weak self] in
            while let self = self, self.isLoading {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard self.isLoading else { break }
                self.elapsedSeconds += 1
                
                if self.elapsedSeconds < 4 {
                    self.loadingProgress = min(0.25, 0.05 + Double(self.elapsedSeconds) * 0.05)
                    self.loadingPhaseText = (self.inputMode == .url) ? "Resolving video metadata..." : "Analyzing input topic..."
                } else if self.elapsedSeconds < 14 {
                    self.loadingProgress = min(0.55, 0.25 + Double(self.elapsedSeconds - 3) * 0.03)
                    let mins = Int(self.targetDurationMinutes)
                    self.loadingPhaseText = "Writing \(mins) min spoken script..."
                } else if self.elapsedSeconds < 28 {
                    self.loadingProgress = min(0.85, 0.55 + Double(self.elapsedSeconds - 13) * 0.02)
                    self.loadingPhaseText = "Refining teleprompter pacing..."
                } else {
                    self.loadingProgress = min(0.96, 0.85 + Double(self.elapsedSeconds - 27) * 0.005)
                    self.loadingPhaseText = "Finalizing presentation (\(self.elapsedSeconds)s)..."
                }
            }
        }
    }
    
    private func stopProgressTracking() {
        progressTask?.cancel()
        progressTask = nil
        loadingProgress = 1.0
    }
}
