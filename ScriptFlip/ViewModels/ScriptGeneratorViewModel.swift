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
        DebugLogService.shared.log("[ViewModel] Usage refreshed: \(userUsage.usedCount)/3 used (\(userUsage.remainingFreeGenerations) remaining).")
    }
    
    public func getDiagnostics() -> NetworkDiagnosticInfo {
        apiService.getDiagnostics()
    }
    
    public var canGenerateFree: Bool {
        subscriptionManager.isUnlimited || !userUsage.isLimitReached
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
        
        let isUnlimited = subscriptionManager.isUnlimited
        
        // Check if user has unlimited access (TestFlight, Debug, Tester override, or active Pro)
        if isUnlimited {
            DebugLogService.shared.log("[ViewModel] Unlimited mode active (TestFlight/Debug=\(SubscriptionManager.isTestFlightOrDebug), TesterOverride=\(SubscriptionManager.isTesterOverrideEnabled), isPro=\(subscriptionManager.isPro)). Bypassing quota check.")
        } else {
            let hasFreeCredits = !userUsage.isLimitReached
            
            // Only if free credits are exhausted do we check live RevenueCat Pro entitlements
            if !hasFreeCredits {
                DebugLogService.shared.log("[ViewModel] Free quota reached. Checking live Pro subscription status...")
                let hasLivePro = await subscriptionManager.fetchCustomerInfo()
                
                if !hasLivePro {
                    let limitMsg = "Subscription required: You have used your 3 free generations for this month. Please subscribe to Pro for unlimited access."
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
            
            // Increment usage count only if NOT in Unlimited / TestFlight mode
            if !subscriptionManager.isUnlimited {
                self.userUsage = usageTracker.incrementUsage()
                DebugLogService.shared.log("[ViewModel] Incremented usage: now \(self.userUsage.usedCount)/3.")
            } else {
                DebugLogService.shared.log("[ViewModel] Unlimited mode: free credit count not decremented.")
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
