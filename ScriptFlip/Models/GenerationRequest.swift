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
        outputCount: Int? = 3
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
        outputCount: Int = 3
    ) {
        self.inputText = content
        self.scriptStyle = style.rawValue
        self.inputType = inputType
        self.outputCount = outputCount
    }
}

/// DTO for raw JSON payload returned by Supabase Edge Function array `[{ hook, body, visualCue, cta }]`.
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

/// Wrapped response payload if returned inside a root container object.
public struct GenerationResponse: Codable, Sendable {
    public let scripts: [GeneratedScriptDTO]
}
