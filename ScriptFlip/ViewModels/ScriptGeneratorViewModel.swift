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
    
    public var generatedScripts: [Script] = []
    
    public var showPaywall: Bool = false
    public var showResults: Bool = false
    public var showDiagnostics: Bool = false
    
    public var userUsage: UserUsage = UserUsage()
    
    private let apiService: ScriptAPIServiceProtocol
    private let usageTracker: UsageTracker
    private let subscriptionManager: SubscriptionManager
    
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
        do {
            self.userUsage = usageTracker.getUsage()
            DebugLogService.shared.log("[ViewModel] Usage refreshed: \(userUsage.usedCount)/3 used (\(userUsage.remainingFreeGenerations) remaining).")
        } catch {
            print("[ScriptGeneratorViewModel] Warning during usage refresh: \(error.localizedDescription)")
            self.userUsage = UserUsage()
        }
    }
    
    public func getDiagnostics() -> NetworkDiagnosticInfo {
        apiService.getDiagnostics()
    }
    
    public var canGenerateFree: Bool {
        subscriptionManager.isPro || !userUsage.isLimitReached
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
        
        // Check if free credits remain
        let hasFreeCredits = !userUsage.isLimitReached
        var isPro = subscriptionManager.isPro
        
        // Only if free credits are exhausted do we check live RevenueCat Pro entitlements
        if !hasFreeCredits && !isPro {
            DebugLogService.shared.log("[ViewModel] Free quota reached. Checking live Pro subscription status...")
            isPro = await subscriptionManager.fetchCustomerInfo()
            
            if !isPro {
                let limitMsg = "Subscription required: You have used your 3 free generations for this month. Please subscribe to Pro for unlimited access."
                DebugLogService.shared.log("[ViewModel] Blocked early: \(limitMsg)")
                self.errorMessage = limitMsg
                self.showPaywall = true
                self.showErrorAlert = true
                return
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
            outputCount: 3
        )
        
        DebugLogService.shared.log("[ViewModel] Dispatching request to APIService for style '\(selectedStyle.rawValue)'...")
        
        do {
            let scripts = try await apiService.generateScripts(request: payload)
            DebugLogService.shared.log("[ViewModel] Successfully received \(scripts.count) scripts from Edge Function.")
            self.generatedScripts = scripts
            
            // Increment usage if not Pro
            if !isPro {
                self.userUsage = usageTracker.incrementUsage()
                DebugLogService.shared.log("[ViewModel] Incremented usage: now \(self.userUsage.usedCount)/3.")
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
                self.errorMessage = apiError.localizedDescription
                self.showErrorAlert = true
            }
        } catch {
            self.isLoading = false
            DebugLogService.shared.log("[ViewModel] Unexpected error caught: \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
            self.showErrorAlert = true
        }
    }
}
