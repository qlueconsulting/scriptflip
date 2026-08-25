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
        if subscriptionManager.isProTierActive {
            DebugLogService.shared.log("[ViewModel] Usage refreshed (PRO): \(userUsage.proUsedThisWeek)/50 weekly, \(userUsage.proUsedThisMonth)/250 monthly.")
        } else {
            DebugLogService.shared.log("[ViewModel] Usage refreshed (FREE): \(userUsage.usedCount)/3 used (\(userUsage.remainingFreeGenerations) remaining).")
        }
    }
    
    public func getDiagnostics() -> NetworkDiagnosticInfo {
        apiService.getDiagnostics()
    }
    
    public var canGenerateFree: Bool {
        if subscriptionManager.isProTierActive {
            return !userUsage.isProLimitReached
        } else {
            return !userUsage.isLimitReached
        }
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
        
        let isPro = subscriptionManager.isProTierActive
        
        // 1. Quota Verification
        if isPro {
            if userUsage.isProWeeklyLimitReached {
                let limitMsg = "Weekly Pro Limit Reached: You have reached your 50 script generations for this week. Your weekly quota will automatically reset."
                DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                self.errorMessage = limitMsg
                self.showErrorAlert = true
                return
            }
            if userUsage.isProMonthlyLimitReached {
                let limitMsg = "Monthly Pro Limit Reached: You have reached your 250 script generations for this month. Your monthly quota will reset next month."
                DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                self.errorMessage = limitMsg
                self.showErrorAlert = true
                return
            }
            DebugLogService.shared.log("[ViewModel] Pro tier active. Quota check passed (\(userUsage.remainingProWeeklyGenerations) weekly / \(userUsage.remainingProMonthlyGenerations) monthly left).")
        } else {
            let hasFreeCredits = !userUsage.isLimitReached
            
            // Only if free credits are exhausted do we check live RevenueCat Pro entitlements
            if !hasFreeCredits {
                DebugLogService.shared.log("[ViewModel] Free quota reached. Checking live Pro subscription status...")
                let hasLivePro = await subscriptionManager.fetchCustomerInfo()
                
                if !hasLivePro {
                    let limitMsg = "Subscription required: You have used your 3 free generations for this month. Upgrade to Pro for 50 scripts/week (250/month)."
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
            
            // Increment usage count for Free or Pro quota
            self.userUsage = usageTracker.incrementUsage(isPro: subscriptionManager.isProTierActive)
            if subscriptionManager.isProTierActive {
                DebugLogService.shared.log("[ViewModel] Incremented Pro usage: \(self.userUsage.proUsedThisWeek)/50 weekly, \(self.userUsage.proUsedThisMonth)/250 monthly.")
            } else {
                DebugLogService.shared.log("[ViewModel] Incremented Free usage: now \(self.userUsage.usedCount)/3.")
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
