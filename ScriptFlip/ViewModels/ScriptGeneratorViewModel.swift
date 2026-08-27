import Foundation
import Observation

/// Main view model powering `ScriptGeneratorView`.
@Observable
@MainActor
public final class ScriptGeneratorViewModel {
    public var inputMode: InputMode = .url
    public var inputText: String = ""
    public var selectedStyle: ScriptStyle = .casual
    
    public var isLoading: Bool = false
    public var errorMessage: String? = nil
    public var showErrorAlert: Bool = false
    public var configurationAlertMessage: String? = nil
    public var showConfigAlert: Bool = false
    public var showMissingCaptionsAlert: Bool = false
    
    public var generatedScripts: [Script] = []
    
    public var showPaywall: Bool = false
    public var showResults: Bool = false
    public var showDiagnostics: Bool = false
    public var showHistory: Bool = false
    public var showAbout: Bool = false
    
    public var userUsage: UserUsage = UserUsage()
    
    private let apiService: ScriptAPIServiceProtocol
    private let usageTracker: UsageTracker
    public let subscriptionManager: SubscriptionManager
    
    public enum InputMode: String, CaseIterable, Identifiable, Sendable {
        case url = "URL (YouTube/Podcast)"
        case rawText = "Raw Transcript / Text"
        
        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .url: return "link"
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
        self.userUsage = usageTracker.getUsage()
        let tier = subscriptionManager.activeTier
        switch tier {
        case .proWeekly:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (PRO WEEKLY): \(userUsage.proUsedThisWeek)/50 weekly (\(userUsage.remainingProWeeklyGenerations) left).")
        case .proMonthly:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (PRO MONTHLY): \(userUsage.proUsedThisMonth)/250 monthly (\(userUsage.remainingProMonthlyGenerations) left).")
        case .free:
            DebugLogService.shared.log("[ViewModel] Usage refreshed (FREE): \(userUsage.usedCount)/3 used (\(userUsage.remainingFreeGenerations) remaining).")
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
            let msg = "Please enter a valid YouTube/Podcast URL or transcript text."
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
                    self.showErrorAlert = true
                    return
                }
            }
        }
        
        self.isLoading = true
        self.errorMessage = nil
        self.showErrorAlert = false
        
        let requestType: GenerationRequest.InputType = (inputMode == .url)
            ? (trimmedInput.contains("youtube") || trimmedInput.contains("youtu.be") ? .youtubeUrl : .podcastUrl)
            : .rawText
            
        let payload = GenerationRequest(
            inputText: trimmedInput,
            scriptStyle: selectedStyle.rawValue,
            inputType: requestType,
            outputCount: 1
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
            self.userUsage = usageTracker.incrementUsage(tier: subscriptionManager.activeTier)
            switch subscriptionManager.activeTier {
            case .proWeekly:
                DebugLogService.shared.log("[ViewModel] Incremented Pro Weekly usage: \(self.userUsage.proUsedThisWeek)/50.")
            case .proMonthly:
                DebugLogService.shared.log("[ViewModel] Incremented Pro Monthly usage: \(self.userUsage.proUsedThisMonth)/250.")
            case .free:
                DebugLogService.shared.log("[ViewModel] Incremented Free usage: \(self.userUsage.usedCount)/3.")
            }
            
            self.isLoading = false
            self.showResults = true
        } catch let apiError as ScriptAPIError {
            self.isLoading = false
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
            self.isLoading = false
            DebugLogService.shared.log("[ViewModel] Unexpected error caught: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
}
