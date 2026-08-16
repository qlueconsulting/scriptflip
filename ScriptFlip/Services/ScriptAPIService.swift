import Foundation

/// Errors that can occur during script generation networking.
public enum ScriptAPIError: LocalizedError, Sendable {
    case configurationError(String)
    case invalidURL(String)
    case notConnectedToInternet
    case cannotFindHost(String)
    case cannotConnectToHost
    case timeout
    case sslError(String)
    case networkError(code: Int, message: String)
    case badRequest(statusCode: Int, responseBody: String)
    case serverError(statusCode: Int, responseBody: String)
    case invalidResponse(statusCode: Int, responseBody: String)
    case edgeFunctionError(String)
    case decodingError(Error, rawBody: String)
    case usageLimitExceeded
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .configurationError(let message):
            return "Configuration Error: Invalid Supabase URL or Anon Key.\n\(message)"
        case .invalidURL(let url):
            return "Configuration Error: Malformed Endpoint URL: \(url)"
        case .notConnectedToInternet:
            return "Network Error: Not Connected to Internet. Please check your Wi-Fi or cellular connection."
        case .cannotFindHost(let host):
            return "Network Error: Server Cannot Be Found (\(host)). Please verify the Supabase project URL."
        case .cannotConnectToHost:
            return "Network Error: Cannot Connect to Server. The remote host refused the connection."
        case .timeout:
            return "Network Error: Request Timed Out (30s). The Edge Function took too long to respond."
        case .sslError(let details):
            return "Network Error: SSL / Security Handshake Error. \(details)"
        case .networkError(let code, let message):
            return "Network Error (\(code)): \(message)"
        case .badRequest(let status, let body):
            return "Bad Request (HTTP \(status)): \(body)"
        case .serverError(let status, let body):
            return "Server Error (HTTP \(status)): \(body)"
        case .invalidResponse(let status, let body):
            return "Unexpected Response (HTTP \(status)): \(body)"
        case .edgeFunctionError(let errorMsg):
            return "Edge Function Error: \(errorMsg)"
        case .decodingError(let error, let rawBody):
            return "Failed to parse script payload: \(error.localizedDescription)\nRaw response: \(rawBody.prefix(300))"
        case .usageLimitExceeded:
            return "Monthly generation limit reached. Upgrade to ScriptFlip Pro for unlimited scripts."
        case .unknown(let details):
            return "An unexpected network error occurred: \(details)"
        }
    }
}

/// Diagnostic information captured during network operations.
public struct NetworkDiagnosticInfo: Sendable {
    public var endpointURL: String
    public var anonKeyStatus: String
    public var hasValidAnonKey: Bool
    public var lastRequestTimestamp: Date?
    public var lastRequestMethod: String?
    public var lastRequestHeaders: [String: String]?
    public var lastRequestBody: String?
    public var lastResponseStatusCode: Int?
    public var lastResponseHeaders: [String: String]?
    public var lastResponseBody: String?
    public var lastErrorMessage: String?
    public var lastDurationMs: Double?
    
    public init(
        endpointURL: String = AppEnvironment.generateScriptsEndpoint,
        anonKeyStatus: String = "Not initialized",
        hasValidAnonKey: Bool = false,
        lastRequestTimestamp: Date? = nil,
        lastRequestMethod: String? = nil,
        lastRequestHeaders: [String: String]? = nil,
        lastRequestBody: String? = nil,
        lastResponseStatusCode: Int? = nil,
        lastResponseHeaders: [String: String]? = nil,
        lastResponseBody: String? = nil,
        lastErrorMessage: String? = nil,
        lastDurationMs: Double? = nil
    ) {
        self.endpointURL = endpointURL
        self.anonKeyStatus = anonKeyStatus
        self.hasValidAnonKey = hasValidAnonKey
        self.lastRequestTimestamp = lastRequestTimestamp
        self.lastRequestMethod = lastRequestMethod
        self.lastRequestHeaders = lastRequestHeaders
        self.lastRequestBody = lastRequestBody
        self.lastResponseStatusCode = lastResponseStatusCode
        self.lastResponseHeaders = lastResponseHeaders
        self.lastResponseBody = lastResponseBody
        self.lastErrorMessage = lastErrorMessage
        self.lastDurationMs = lastDurationMs
    }
}

/// Service protocol for network interaction and mock testing.
public protocol ScriptAPIServiceProtocol: Sendable {
    func generateScripts(request: GenerationRequest) async throws -> [Script]
    func getDiagnostics() -> NetworkDiagnosticInfo
}

/// Network layer service interfacing with Supabase Edge Function `POST /functions/v1/generate-scripts`.
public final class ScriptAPIService: ScriptAPIServiceProtocol, @unchecked Sendable {
    private let baseURL: String
    private let supabaseAnonKey: String
    private let session: URLSession
    
    private let lock = NSLock()
    private var diagnostics: NetworkDiagnosticInfo
    
    public init(
        baseURL: String = AppEnvironment.generateScriptsEndpoint,
        supabaseAnonKey: String = AppEnvironment.supabaseAnonKey,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.supabaseAnonKey = supabaseAnonKey
        self.session = session
        
        let keyValid = !supabaseAnonKey.isEmpty && !supabaseAnonKey.contains("your-")
        let keySummary = keyValid 
            ? "Present (\(supabaseAnonKey.prefix(12))..., length: \(supabaseAnonKey.count))"
            : "MISSING or Placeholder"
            
        self.diagnostics = NetworkDiagnosticInfo(
            endpointURL: baseURL,
            anonKeyStatus: keySummary,
            hasValidAnonKey: keyValid
        )
    }
    
    public func getDiagnostics() -> NetworkDiagnosticInfo {
        lock.lock()
        defer { lock.unlock() }
        return diagnostics
    }
    
    public func generateScripts(request: GenerationRequest) async throws -> [Script] {
        let startTime = Date()
        
        // 1. PRE-FLIGHT VERIFICATION
        guard !baseURL.isEmpty, let url = URL(string: baseURL), url.scheme != nil, let host = url.host, !host.isEmpty else {
            let error = ScriptAPIError.configurationError("Invalid or empty Supabase Endpoint URL: '\(baseURL)'")
            updateDiagnosticsError(error.localizedDescription)
            throw error
        }
        
        guard !supabaseAnonKey.isEmpty && !supabaseAnonKey.contains("your-") else {
            let error = ScriptAPIError.configurationError("Missing or placeholder Supabase Anon Key. Ensure Config.xcconfig / Environment defines a valid JWT token.")
            updateDiagnosticsError(error.localizedDescription)
            throw error
        }
        
        // 2. BUILD REQUEST & HEADERS
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 30
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(supabaseAnonKey, forHTTPHeaderField: "apikey")
        urlRequest.setValue("Bearer \(supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        
        let requestBodyData: Data
        do {
            requestBodyData = try JSONEncoder().encode(request)
            urlRequest.httpBody = requestBodyData
        } catch {
            let err = ScriptAPIError.decodingError(error, rawBody: "Failed to encode GenerationRequest JSON.")
            updateDiagnosticsError(err.localizedDescription)
            throw err
        }
        
        let requestBodyString = String(data: requestBodyData, encoding: .utf8) ?? ""
        let headersDict = urlRequest.allHTTPHeaderFields ?? [:]
        
        // Pre-Flight Debug Logging
        print("================ [ScriptAPIService] PRE-FLIGHT REQUEST ================")
        print("[ScriptAPIService] Destination URL: \(url.absoluteString)")
        print("[ScriptAPIService] Method: POST | Timeout: 30s")
        print("[ScriptAPIService] Headers: \(headersDict.map { "\($0.key): \($0.key.lowercased().contains("auth") || $0.key.lowercased() == "apikey" ? "\($0.value.prefix(15))..." : $0.value)" }.joined(separator: ", "))")
        print("[ScriptAPIService] Payload (\(requestBodyData.count) bytes): \(requestBodyString)")
        print("=======================================================================")
        
        // 3. EXECUTE NETWORK CALL
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let urlError as URLError {
            let duration = Date().timeIntervalSince(startTime) * 1000
            let mappedError: ScriptAPIError
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                mappedError = .notConnectedToInternet
            case .cannotFindHost:
                mappedError = .cannotFindHost(url.host ?? baseURL)
            case .cannotConnectToHost:
                mappedError = .cannotConnectToHost
            case .timedOut:
                mappedError = .timeout
            case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate, .serverCertificateNotYetValid:
                mappedError = .sslError(urlError.localizedDescription)
            default:
                mappedError = .networkError(code: urlError.code.rawValue, message: urlError.localizedDescription)
            }
            
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: nil,
                responseHeaders: nil,
                responseBody: "URLError Code \(urlError.code.rawValue): \(urlError.localizedDescription)",
                errorMessage: mappedError.localizedDescription,
                durationMs: duration
            )
            
            print("[ScriptAPIService] URLError encountered: \(mappedError.localizedDescription)")
            throw mappedError
        } catch {
            let duration = Date().timeIntervalSince(startTime) * 1000
            let mappedError = ScriptAPIError.unknown(error.localizedDescription)
            
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: nil,
                responseHeaders: nil,
                responseBody: "Error: \(error.localizedDescription)",
                errorMessage: mappedError.localizedDescription,
                durationMs: duration
            )
            
            print("[ScriptAPIService] Unknown network error: \(error.localizedDescription)")
            throw mappedError
        }
        
        let duration = Date().timeIntervalSince(startTime) * 1000
        guard let httpResponse = response as? HTTPURLResponse else {
            let mappedError = ScriptAPIError.unknown("Non-HTTP response received from server.")
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: nil,
                responseHeaders: nil,
                responseBody: "Non-HTTP Response",
                errorMessage: mappedError.localizedDescription,
                durationMs: duration
            )
            throw mappedError
        }
        
        let responseBodyString = String(data: data, encoding: .utf8) ?? "<Binary or Non-UTF8 Response (\(data.count) bytes)>"
        let responseHeadersDict = (httpResponse.allHeaderFields as? [String: String]) ?? [:]
        
        print("================ [ScriptAPIService] RESPONSE RECEIVED ================")
        print("[ScriptAPIService] Status Code: \(httpResponse.statusCode)")
        print("[ScriptAPIService] Duration: \(String(format: "%.1f", duration))ms")
        print("[ScriptAPIService] Response Body (\(data.count) bytes): \(responseBodyString.prefix(500))")
        print("======================================================================")
        
        // 4. HTTP STATUS CODE VERIFICATION
        if httpResponse.statusCode == 400 {
            let error = ScriptAPIError.badRequest(statusCode: 400, responseBody: responseBodyString)
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: 400,
                responseHeaders: responseHeadersDict,
                responseBody: responseBodyString,
                errorMessage: error.localizedDescription,
                durationMs: duration
            )
            throw error
        } else if httpResponse.statusCode == 429 {
            let error = ScriptAPIError.usageLimitExceeded
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: 429,
                responseHeaders: responseHeadersDict,
                responseBody: responseBodyString,
                errorMessage: error.localizedDescription,
                durationMs: duration
            )
            throw error
        } else if (500...599).contains(httpResponse.statusCode) {
            let error = ScriptAPIError.serverError(statusCode: httpResponse.statusCode, responseBody: responseBodyString)
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeadersDict,
                responseBody: responseBodyString,
                errorMessage: error.localizedDescription,
                durationMs: duration
            )
            throw error
        } else if !(200...299).contains(httpResponse.statusCode) {
            let error = ScriptAPIError.invalidResponse(statusCode: httpResponse.statusCode, responseBody: responseBodyString)
            recordDiagnostics(
                requestTimestamp: startTime,
                method: "POST",
                headers: headersDict,
                requestBody: requestBodyString,
                statusCode: httpResponse.statusCode,
                responseHeaders: responseHeadersDict,
                responseBody: responseBodyString,
                errorMessage: error.localizedDescription,
                durationMs: duration
            )
            throw error
        }
        
        // 5. PARSE RESPONSE PAYLOAD
        let decoder = JSONDecoder()
        var dtos: [GeneratedScriptDTO] = []
        
        // Check for wrapped { error: "..." }
        if let responseWrapper = try? decoder.decode(GenerationResponse.self, from: data) {
            if let errorMsg = responseWrapper.error, !errorMsg.isEmpty {
                let error = ScriptAPIError.edgeFunctionError(errorMsg)
                recordDiagnostics(
                    requestTimestamp: startTime,
                    method: "POST",
                    headers: headersDict,
                    requestBody: requestBodyString,
                    statusCode: httpResponse.statusCode,
                    responseHeaders: responseHeadersDict,
                    responseBody: responseBodyString,
                    errorMessage: error.localizedDescription,
                    durationMs: duration
                )
                throw error
            }
            if let resolved = responseWrapper.resolvedScripts, !resolved.isEmpty {
                dtos = resolved
            }
        }
        
        if dtos.isEmpty {
            if let directArray = try? decoder.decode([GeneratedScriptDTO].self, from: data) {
                dtos = directArray
            } else if let single = try? decoder.decode(GeneratedScriptDTO.self, from: data) {
                dtos = [single]
            } else {
                do {
                    dtos = try decoder.decode([GeneratedScriptDTO].self, from: data)
                } catch {
                    let decodingError = ScriptAPIError.decodingError(error, rawBody: responseBodyString)
                    recordDiagnostics(
                        requestTimestamp: startTime,
                        method: "POST",
                        headers: headersDict,
                        requestBody: requestBodyString,
                        statusCode: httpResponse.statusCode,
                        responseHeaders: responseHeadersDict,
                        responseBody: responseBodyString,
                        errorMessage: decodingError.localizedDescription,
                        durationMs: duration
                    )
                    throw decodingError
                }
            }
        }
        
        recordDiagnostics(
            requestTimestamp: startTime,
            method: "POST",
            headers: headersDict,
            requestBody: requestBodyString,
            statusCode: httpResponse.statusCode,
            responseHeaders: responseHeadersDict,
            responseBody: responseBodyString,
            errorMessage: nil,
            durationMs: duration
        )
        
        let selectedStyle = ScriptStyle(rawValue: request.scriptStyle) ?? .casual
        return dtos.enumerated().map { index, dto in
            Script(dto: dto, index: index + 1, style: selectedStyle)
        }
    }
    
    private func updateDiagnosticsError(_ errorMessage: String) {
        lock.lock()
        defer { lock.unlock() }
        diagnostics.lastErrorMessage = errorMessage
        diagnostics.lastRequestTimestamp = Date()
    }
    
    private func recordDiagnostics(
        requestTimestamp: Date,
        method: String,
        headers: [String: String],
        requestBody: String,
        statusCode: Int?,
        responseHeaders: [String: String]?,
        responseBody: String?,
        errorMessage: String?,
        durationMs: Double
    ) {
        lock.lock()
        defer { lock.unlock() }
        diagnostics.lastRequestTimestamp = requestTimestamp
        diagnostics.lastRequestMethod = method
        diagnostics.lastRequestHeaders = headers
        diagnostics.lastRequestBody = requestBody
        diagnostics.lastResponseStatusCode = statusCode
        diagnostics.lastResponseHeaders = responseHeaders
        diagnostics.lastResponseBody = responseBody
        diagnostics.lastErrorMessage = errorMessage
        diagnostics.lastDurationMs = durationMs
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
