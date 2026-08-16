import XCTest
@testable import ScriptFlip

/// Custom Mock URLProtocol to intercept URLSession requests during unit testing.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) public static var requestHandler: (@Sendable (URLRequest) throws -> (HTTPURLResponse, Data?))?

    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }

    override func startLoading() {
        guard let handler = MockURLProtocol.requestHandler else {
            XCTFail("Handler is not set.")
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

final class ScriptAPIServiceTests: XCTestCase {
    private var session: URLSession?

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    // MARK: - Successful Script Array Payload Parsing

    func testGenerateScriptsSuccessParsing() async throws {
        let jsonResponse = """
        [
            {
                "hook": "Stop making this huge viral mistake!",
                "body": "Here is the step by step blueprint to double video retention in 10 seconds.",
                "visualCue": "Fast zoom-in on face with red alert graphic.",
                "cta": "Tap follow for daily video tips!"
            },
            {
                "hook": "3 quick tools for short form creators.",
                "body": "Tool 1 extracts hooks, Tool 2 formats teleprompter, Tool 3 automates captioning.",
                "visualCue": "Screen recording showing timeline editor.",
                "cta": "Save this reel for later!"
            }
        ]
        """
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) ?? HTTPURLResponse()
            return (response, jsonResponse.data(using: .utf8))
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "https://youtube.com/watch?v=123", scriptStyle: "casual")
        let scripts = try await service.generateScripts(request: request)

        XCTAssertEqual(scripts.count, 2)
        XCTAssertEqual(scripts[0].hook, "Stop making this huge viral mistake!")
        XCTAssertEqual(scripts[0].body, "Here is the step by step blueprint to double video retention in 10 seconds.")
        XCTAssertEqual(scripts[0].visualCue, "Fast zoom-in on face with red alert graphic.")
        XCTAssertEqual(scripts[0].cta, "Tap follow for daily video tips!")
        XCTAssertEqual(scripts[1].hook, "3 quick tools for short form creators.")
        
        let diagnostics = service.getDiagnostics()
        XCTAssertEqual(diagnostics.lastResponseStatusCode, 200)
        XCTAssertTrue(diagnostics.hasValidAnonKey)
    }

    // MARK: - Wrapped Data Response Parsing

    func testGenerateScriptsWrappedDataParsing() async throws {
        let jsonResponse = """
        {
            "data": [
                {
                    "hook": "Here is how to create 10 Shorts a day",
                    "body": "Step 1 is repurposing long podcasts. Step 2 is teleprompter recording.",
                    "visualCue": "Phone screenshot showing prompter app",
                    "cta": "Link in bio to download!"
                }
            ]
        }
        """
        
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) ?? HTTPURLResponse()
            return (response, jsonResponse.data(using: .utf8))
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample podcast", scriptStyle: "expert")
        let scripts = try await service.generateScripts(request: request)

        XCTAssertEqual(scripts.count, 1)
        XCTAssertEqual(scripts.first?.hook, "Here is how to create 10 Shorts a day")
    }

    // MARK: - Error Handling Tests

    func testGenerateScripts400BadRequest() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 400,
                httpVersion: nil,
                headerFields: nil
            ) ?? HTTPURLResponse()
            return (response, "Invalid input parameters".data(using: .utf8))
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "", scriptStyle: "casual")
        
        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected bad request error")
        } catch let error as ScriptAPIError {
            if case .badRequest(let status, let body) = error {
                XCTAssertEqual(status, 400)
                XCTAssertTrue(body.contains("Invalid input parameters"))
            } else {
                XCTFail("Expected .badRequest error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateScripts500ServerError() async {
        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 500,
                httpVersion: nil,
                headerFields: nil
            ) ?? HTTPURLResponse()
            return (response, "Internal Server Error".data(using: .utf8))
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample transcript", scriptStyle: "expert")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected 500 server error")
        } catch let error as ScriptAPIError {
            if case .serverError(let code, let body) = error {
                XCTAssertEqual(code, 500)
                XCTAssertTrue(body.contains("Internal Server Error"))
            } else {
                XCTFail("Expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGenerateScriptsTimeoutError() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.timedOut)
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample transcript", scriptStyle: "casual")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected timeout error")
        } catch let error as ScriptAPIError {
            if case .timeout = error {
                XCTAssertTrue(true)
            } else {
                XCTFail("Expected .timeout error, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - Pre-Flight Validation Tests

    func testPreflightValidationInvalidURL() async {
        let service = ScriptAPIService(
            baseURL: "",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample input", scriptStyle: "casual")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected configuration error for empty URL")
        } catch let error as ScriptAPIError {
            if case .configurationError(let msg) = error {
                XCTAssertTrue(msg.contains("Invalid or empty Supabase Endpoint URL"))
            } else {
                XCTFail("Expected .configurationError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let diagnostics = service.getDiagnostics()
        XCTAssertNotNil(diagnostics.lastErrorMessage)
        XCTAssertTrue(diagnostics.lastErrorMessage?.contains("Invalid or empty") ?? false)
    }

    func testPreflightValidationMissingOrPlaceholderAnonKey() async {
        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "your-anon-key-here",
            session: session ?? .shared
        )

        let initialDiagnostics = service.getDiagnostics()
        XCTAssertFalse(initialDiagnostics.hasValidAnonKey)
        XCTAssertEqual(initialDiagnostics.anonKeyStatus, "MISSING or Placeholder")

        let request = GenerationRequest(inputText: "Sample input", scriptStyle: "casual")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected configuration error for placeholder key")
        } catch let error as ScriptAPIError {
            if case .configurationError(let msg) = error {
                XCTAssertTrue(msg.contains("Missing or placeholder Supabase Anon Key"))
            } else {
                XCTFail("Expected .configurationError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let diagnostics = service.getDiagnostics()
        XCTAssertNotNil(diagnostics.lastErrorMessage)
        XCTAssertTrue(diagnostics.lastErrorMessage?.contains("Missing or placeholder") ?? false)
    }

    // MARK: - Edge Function Error & Diagnostic Payload Tracking Tests

    func testEdgeFunctionErrorPayloadTracking() async {
        let jsonResponse = """
        {
            "error": "OpenAI quota exceeded for edge function."
        }
        """

        MockURLProtocol.requestHandler = { request in
            let url = request.url ?? URL(fileURLWithPath: "/")
            let response = HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            ) ?? HTTPURLResponse()
            return (response, jsonResponse.data(using: .utf8))
        }

        let service = ScriptAPIService(
            baseURL: "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample input", scriptStyle: "casual")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected edge function error")
        } catch let error as ScriptAPIError {
            if case .edgeFunctionError(let message) = error {
                XCTAssertEqual(message, "OpenAI quota exceeded for edge function.")
            } else {
                XCTFail("Expected .edgeFunctionError, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let diagnostics = service.getDiagnostics()
        XCTAssertEqual(diagnostics.lastResponseStatusCode, 200)
        XCTAssertNotNil(diagnostics.lastErrorMessage)
        XCTAssertTrue(diagnostics.lastErrorMessage?.contains("OpenAI quota exceeded") ?? false)
        XCTAssertNotNil(diagnostics.lastDurationMs)
        XCTAssertNotNil(diagnostics.lastRequestBody)
    }

    func testNetworkCannotFindHostErrorTracking() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotFindHost)
        }

        let service = ScriptAPIService(
            baseURL: "https://invalid-host-supabase.co/functions/v1/generate-scripts",
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.test_anon_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample input", scriptStyle: "casual")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected cannotFindHost error")
        } catch let error as ScriptAPIError {
            if case .cannotFindHost(let host) = error {
                XCTAssertEqual(host, "invalid-host-supabase.co")
            } else {
                XCTFail("Expected .cannotFindHost, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let diagnostics = service.getDiagnostics()
        XCTAssertNil(diagnostics.lastResponseStatusCode)
        XCTAssertNotNil(diagnostics.lastErrorMessage)
        XCTAssertTrue(diagnostics.lastErrorMessage?.contains("cannotFindHost") ?? false || diagnostics.lastErrorMessage?.contains("Server Cannot Be Found") ?? false)
    }
}
