import Foundation

/// Request payload for Supabase Edge Function `/functions/v1/generate-scripts`.
public struct GenerationRequest: Codable, Sendable {
    public let inputText: String
    public let scriptStyle: String
    public let inputType: InputType?
    public let outputCount: Int?
    
    public enum InputType: String, Codable, Sendable {
        case rawText = "text"
        case youtubeUrl = "youtube"
        case podcastUrl = "podcast"
    }

    public init(
        inputText: String,
        scriptStyle: String,
        inputType: InputType? = nil,
        outputCount: Int? = 1
    ) {
        self.inputText = inputText
        self.scriptStyle = scriptStyle
        self.inputType = inputType
        self.outputCount = outputCount
    }
    
    public init(
        inputType: InputType,
        content: String,
        style: ScriptStyle,
        outputCount: Int = 1
    ) {
        self.inputText = content
        self.scriptStyle = style.rawValue
        self.inputType = inputType
        self.outputCount = outputCount
    }
}

/// DTO for single universal script payload returned by Supabase Edge Function:
/// `{ title, hook, body, callToAction, estimatedDuration, visualCues }`
public struct UniversalScriptDTO: Codable, Sendable {
    public let title: String?
    public let hook: String
    public let body: String
    public let callToAction: String?
    public let cta: String?
    public let estimatedDuration: String?
    public let visualCues: [String]?
    public let visualCue: String?
    
    public init(
        title: String? = nil,
        hook: String,
        body: String,
        callToAction: String? = nil,
        cta: String? = nil,
        estimatedDuration: String? = "30-45s",
        visualCues: [String]? = nil,
        visualCue: String? = nil
    ) {
        self.title = title
        self.hook = hook
        self.body = body
        self.callToAction = callToAction
        self.cta = cta ?? callToAction
        self.estimatedDuration = estimatedDuration
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

/// Wrapped response payload if returned inside a root container object (`{ script: { ... } }`, `{ data: [...] }` or `{ scripts: [...] }`).
public struct GenerationResponse: Codable, Sendable {
    public let script: UniversalScriptDTO?
    public let data: [UniversalScriptDTO]?
    public let scripts: [UniversalScriptDTO]?
    public let error: String?
    
    public init(
        script: UniversalScriptDTO? = nil,
        data: [UniversalScriptDTO]? = nil,
        scripts: [UniversalScriptDTO]? = nil,
        error: String? = nil
    ) {
        self.script = script
        self.data = data
        self.scripts = scripts
        self.error = error
    }
    
    public var resolvedScripts: [UniversalScriptDTO]? {
        if let single = script {
            return [single]
        }
        return data ?? scripts
    }
}
