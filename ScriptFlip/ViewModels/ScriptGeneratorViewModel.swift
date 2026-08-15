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
    public var generatedScripts: [Script] = []
    
    public var showPaywall: Bool = false
    public var showResults: Bool = false
    
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
        refreshUsage()
    }
    
    public func refreshUsage() {
        self.userUsage = usageTracker.getUsage()
    }
    
    public var canGenerateFree: Bool {
        subscriptionManager.isPro || !userUsage.isLimitReached
    }
    
    public func generateScripts() async {
        let trimmedInput = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            self.errorMessage = "Please enter a valid YouTube/Podcast URL or transcript text."
            return
        }
        
        // Check RevenueCat user entitlements before every generation request
        let isPro = await subscriptionManager.fetchCustomerInfo()
        refreshUsage()
        
        // 3 free generations limit enforcement: trigger paywall on 4th attempt if not Pro
        if !isPro && userUsage.isLimitReached {
            self.showPaywall = true
            return
        }
        
        self.isLoading = true
        self.errorMessage = nil
        
        let requestType: GenerationRequest.InputType = (inputMode == .url)
            ? (trimmedInput.contains("youtube") || trimmedInput.contains("youtu.be") ? .youtubeUrl : .podcastUrl)
            : .rawText
            
        let payload = GenerationRequest(
            inputText: trimmedInput,
            scriptStyle: selectedStyle.rawValue,
            inputType: requestType,
            outputCount: 3
        )
        
        do {
            let scripts = try await apiService.generateScripts(request: payload)
            self.generatedScripts = scripts
            
            // Increment usage if not Pro
            if !isPro {
                self.userUsage = usageTracker.incrementUsage()
            }
            
            self.isLoading = false
            self.showResults = true
        } catch {
            self.isLoading = false
            self.errorMessage = error.localizedDescription
        }
    }
}
