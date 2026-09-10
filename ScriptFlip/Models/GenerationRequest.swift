import Foundation

/// Request payload for Supabase Edge Function `/functions/v1/generate-scripts`.
public struct GenerationRequest: Codable, Sendable {
    public let inputText: String
    public let scriptStyle: String
    public let inputType: InputType?
    public let outputCount: Int?
    public let targetDurationMinutes: Int?
    
    public let anonymousUserId: String?
    public let clientTier: String?
    
    public enum InputType: String, Codable, Sendable {
        case rawText = "text"
        case videoUrl = "video"
        case youtubeUrl = "youtube"
        case podcastUrl = "podcast"
    }

    public init(
        inputText: String,
        scriptStyle: String,
        inputType: InputType? = nil,
        outputCount: Int? = 1,
        targetDurationMinutes: Int? = nil,
        anonymousUserId: String? = nil,
        clientTier: String? = nil
    ) {
        self.inputText = inputText
        self.scriptStyle = scriptStyle
        self.inputType = inputType
        self.outputCount = outputCount
        self.targetDurationMinutes = targetDurationMinutes
        self.anonymousUserId = anonymousUserId
        self.clientTier = clientTier
    }
    
    public init(
        inputType: InputType,
        content: String,
        style: ScriptStyle,
        outputCount: Int = 1,
        targetDurationMinutes: Int? = nil,
        anonymousUserId: String? = nil,
        clientTier: String? = nil
    ) {
        self.inputText = content
        self.scriptStyle = style.rawValue
        self.inputType = inputType
        self.outputCount = outputCount
        self.targetDurationMinutes = targetDurationMinutes
        self.anonymousUserId = anonymousUserId
        self.clientTier = clientTier
    }
}

/// DTO for single universal script payload returned by Supabase Edge Function:
/// `{ title, hook, body, callToAction, estimatedDuration, keyTakeaway }`
public struct UniversalScriptDTO: Codable, Sendable {
    public let title: String?
    public let hook: String
    public let body: String
    public let callToAction: String?
    public let cta: String?
    public let estimatedDuration: String?
    public let keyTakeaway: String?
    public let visualCues: [String]?
    public let visualCue: String?
    
    public init(
        title: String? = nil,
        hook: String,
        body: String,
        callToAction: String? = nil,
        cta: String? = nil,
        estimatedDuration: String? = "3-5 min",
        keyTakeaway: String? = nil,
        visualCues: [String]? = nil,
        visualCue: String? = nil
    ) {
        self.title = title
        self.hook = hook
        self.body = body
        self.callToAction = callToAction
        self.cta = cta ?? callToAction
        self.estimatedDuration = estimatedDuration
        self.keyTakeaway = keyTakeaway
        self.visualCues = visualCues
        self.visualCue = visualCue
    }
    
    public var resolvedCTA: String {
        callToAction ?? cta ?? "Save and share this video!"
    }
    
    public var resolvedVisualCue: String {
        if let cues = visualCues, !cues.isEmpty {
            return cues.joined(separator: "; ")
        }
        return visualCue ?? "Direct camera eye-contact and vibrant text overlays"
    }
}

/// Backward-compatible DTO for array item `{ hook, body, visualCue, cta }`.
public struct GeneratedScriptDTO: Codable, Sendable {
    public let hook: String
    public let body: String
    public let visualCue: String
    public let cta: String
    
    public init(hook: String, body: String, visualCue: String, cta: String) {
        self.hook = hook
        self.body = body
        self.visualCue = visualCue
        self.cta = cta
    }
}

/// Quota information returned by Supabase backend inside GenerationResponse.
public struct ServerQuotaResponse: Codable, Sendable {
    public let allowed: Bool?
    public let remaining: Int?
    public let limit: Int?
    public let tier: String?
    public let freeUsed: Int?
    public let proWeekUsed: Int?
    public let proMonthUsed: Int?
    
    enum CodingKeys: String, CodingKey {
        case allowed
        case remaining
        case limit
        case tier
        case freeUsed = "free_used"
        case proWeekUsed = "pro_week_used"
        case proMonthUsed = "pro_month_used"
    }
    
    public init(
        allowed: Bool? = nil,
        remaining: Int? = nil,
        limit: Int? = nil,
        tier: String? = nil,
        freeUsed: Int? = nil,
        proWeekUsed: Int? = nil,
        proMonthUsed: Int? = nil
    ) {
        self.allowed = allowed
        self.remaining = remaining
        self.limit = limit
        self.tier = tier
        self.freeUsed = freeUsed
        self.proWeekUsed = proWeekUsed
        self.proMonthUsed = proMonthUsed
    }
}

/// Wrapped response payload if returned inside a root container object (`{ script: { ... } }`, `{ data: [...] }` or `{ scripts: [...] }`).
public struct GenerationResponse: Codable, Sendable {
    public let script: UniversalScriptDTO?
    public let data: [UniversalScriptDTO]?
    public let scripts: [UniversalScriptDTO]?
    public let quota: ServerQuotaResponse?
    public let error: String?
    
    public init(
        script: UniversalScriptDTO? = nil,
        data: [UniversalScriptDTO]? = nil,
        scripts: [UniversalScriptDTO]? = nil,
        quota: ServerQuotaResponse? = nil,
        error: String? = nil
    ) {
        self.script = script
        self.data = data
        self.scripts = scripts
        self.quota = quota
        self.error = error
    }
    
    public var resolvedScripts: [UniversalScriptDTO]? {
        if let single = script {
            return [single]
        }
        return data ?? scripts
    }
}
