import Foundation

/// Errors that can occur during script generation networking.
public enum ScriptAPIError: LocalizedError, Sendable {
    case invalidURL
    case networkError(Error)
    case timeout
    case badRequest(String)
    case serverError(statusCode: Int)
    case invalidResponse(statusCode: Int)
    case decodingError(Error)
    case usageLimitExceeded
    case unknown
    
    public var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API Endpoint URL."
        case .timeout:
            return "Network request timed out. Please check your connection and try again."
        case .badRequest(let message):
            return "Bad Request (400): \(message)"
        case .serverError(let code):
            return "Server Error (\(code)): Supabase Edge Function encountered an error."
        case .networkError(let error):
            return "Network connection error: \(error.localizedDescription)"
        case .invalidResponse(let code):
            return "Server returned unexpected status code: \(code)."
        case .decodingError(let error):
            return "Failed to parse script payload: \(error.localizedDescription)"
        case .usageLimitExceeded:
            return "Monthly generation limit reached. Upgrade to ScriptFlip Pro for unlimited scripts."
        case .unknown:
            return "An unexpected network error occurred."
        }
    }
}

/// Service protocol for network interaction and mock testing.
public protocol ScriptAPIServiceProtocol: Sendable {
    func generateScripts(request: GenerationRequest) async throws -> [Script]
}

/// Network layer service interfacing with Supabase Edge Function `POST /functions/v1/generate-scripts`.
public final class ScriptAPIService: ScriptAPIServiceProtocol, Sendable {
    private let baseURL: String
    private let supabaseAnonKey: String
    private let session: URLSession
    
    public init(
        baseURL: String = AppEnvironment.generateScriptsEndpoint,
        supabaseAnonKey: String = AppEnvironment.supabaseAnonKey,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.session = session
    }
    
    public func generateScripts(request: GenerationRequest) async throws -> [Script] {
        // Fallback for placeholder endpoint during offline preview
        if baseURL.contains("your-supabase-project") {
            try await Task.sleep(nanoseconds: 1_200_000_000)
            return Self.mockScripts(for: request)
        }
        
        guard let url = URL(string: baseURL) else {
            throw ScriptAPIError.invalidURL
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        do {
            urlRequest.httpBody = try JSONEncoder().encode(request)
        } catch {
            throw ScriptAPIError.decodingError(error)
        }
        
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            if urlError.code == .timedOut {
                throw ScriptAPIError.timeout
            }
            throw ScriptAPIError.networkError(urlError)
        } catch {
            throw ScriptAPIError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ScriptAPIError.unknown
        }
        
        if httpResponse.statusCode == 400 {
            let errorText = String(data: data, encoding: .utf8) ?? "Invalid input parameters."
            throw ScriptAPIError.badRequest(errorText)
        } else if httpResponse.statusCode == 429 {
            throw ScriptAPIError.usageLimitExceeded
        } else if (500...599).contains(httpResponse.statusCode) {
            throw ScriptAPIError.serverError(statusCode: httpResponse.statusCode)
        } else if !(200...299).contains(httpResponse.statusCode) {
            throw ScriptAPIError.invalidResponse(statusCode: httpResponse.statusCode)
        }
        
        // Parse returned JSON payload array containing [{ hook, body, visualCue, cta }]
        let decoder = JSONDecoder()
        var dtos: [GeneratedScriptDTO] = []
        
        if let directArray = try? decoder.decode([GeneratedScriptDTO].self, from: data) {
            dtos = directArray
        } else if let wrapped = try? decoder.decode(GenerationResponse.self, from: data) {
            dtos = wrapped.scripts
        } else {
            // Attempt to parse single object if returned
            if let single = try? decoder.decode(GeneratedScriptDTO.self, from: data) {
                dtos = [single]
            } else {
                do {
                    dtos = try decoder.decode([GeneratedScriptDTO].self, from: data)
                } catch {
                    throw ScriptAPIError.decodingError(error)
                }
            }
        }
        
        let selectedStyle = ScriptStyle(rawValue: request.scriptStyle) ?? .casual
        return dtos.enumerated().map { index, dto in
            Script(dto: dto, index: index + 1, style: selectedStyle)
        }
    }
    
    /// Generates contextually realistic scripts for mock/demo testing.
    public static func mockScripts(for request: GenerationRequest) -> [Script] {
        let snippet = String(request.inputText.prefix(30))
        let style = ScriptStyle(rawValue: request.scriptStyle) ?? .casual
        
        return [
            Script(
                dto: GeneratedScriptDTO(
                    hook: "Stop scrolling if you're still relying on raw text for '\(snippet)...'!",
                    body: "Most creators spend hours editing, but forget that retention drops in the first 3 seconds. Keep hooks short and add visual cues.",
                    visualCue: "Point directly at camera with high-contrast text overlay.",
                    cta: "Save this video right now for your next Short or Reel!"
                ),
                index: 1,
                style: style
            ),
            Script(
                dto: GeneratedScriptDTO(
                    hook: "Here is how I turned '\(snippet)' into 100k views without showing my face.",
                    body: "I structured every Short into three clear blocks: 3-second hook, core value delivery, and a comment-driven call to action.",
                    visualCue: "Show phone screen with viral view analytics animation.",
                    cta: "Comment 'FLIP' below to get the full teleprompter template!"
                ),
                index: 2,
                style: style
            ),
            Script(
                dto: GeneratedScriptDTO(
                    hook: "3 tools that turn long videos into viral Shorts in 60 seconds.",
                    body: "Tool 1 extracts the top hook. Tool 2 generates visual cues. Tool 3 streams directly to your teleprompter.",
                    visualCue: "Fast cuts showing editing software timeline.",
                    cta: "Follow @ScriptFlip for daily short-form video strategies!"
                ),
                index: 3,
                style: style
            )
        ]
    }
}
