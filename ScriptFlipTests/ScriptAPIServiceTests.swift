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
            supabaseAnonKey: "test_key",
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
            supabaseAnonKey: "test_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "", scriptStyle: "casual")
        
        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected bad request error")
        } catch let error as ScriptAPIError {
            if case .badRequest(let message) = error {
                XCTAssertTrue(message.contains("Invalid input parameters"))
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
            supabaseAnonKey: "test_key",
            session: session ?? .shared
        )

        let request = GenerationRequest(inputText: "Sample transcript", scriptStyle: "expert")

        do {
            _ = try await service.generateScripts(request: request)
            XCTFail("Expected 500 server error")
        } catch let error as ScriptAPIError {
            if case .serverError(let code) = error {
                XCTAssertEqual(code, 500)
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
            supabaseAnonKey: "test_key",
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
}
