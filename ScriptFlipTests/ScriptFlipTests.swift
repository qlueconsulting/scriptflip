import XCTest
@testable import ScriptFlip

final class ScriptFlipTests: XCTestCase {
    
    // MARK: - Script Parsing & Model Tests
    
    func testScriptFullSpokenTextFormatting() {
        let script = Script(
            title: "Test Script",
            style: .casual,
            sections: [
                ScriptSection(timeRange: "0:00 - 0:03", sectionType: .hook, spokenText: "Stop scrolling!", visualCue: "Zoom in"),
                ScriptSection(timeRange: "0:03 - 0:10", sectionType: .body, spokenText: "Here is the value.", visualCue: "Point down")
            ],
            keyTakeaway: "Hooks work."
        )
        
        let expected = "[Hook (0-3s)]\nStop scrolling!\n\n[Core Value]\nHere is the value."
        XCTAssertEqual(script.fullSpokenText, expected)
    }
    
    // MARK: - Usage Limit Logic Tests
    
    func testUserUsageCalculations() {
        let usageNew = UserUsage(usedCount: 1)
        XCTAssertEqual(usageNew.remainingFreeGenerations, 2)
        XCTAssertFalse(usageNew.isLimitReached)
        
        let usageReached = UserUsage(usedCount: 3)
        XCTAssertEqual(usageReached.remainingFreeGenerations, 0)
        XCTAssertTrue(usageReached.isLimitReached)
    }
    
    // MARK: - Mock API Response Handling
    
    func testMockAPIReturnsCorrectScriptCount() async throws {
        let apiService = ScriptAPIService()
        let request = GenerationRequest(
            inputType: .rawText,
            content: "Testing raw text input content for short video",
            style: .directResponse,
            outputCount: 3
        )
        
        let scripts = try await apiService.generateScripts(request: request)
        XCTAssertEqual(scripts.count, 3)
        XCTAssertEqual(scripts.first?.style, .directResponse)
        XCTAssertGreaterThan(scripts.first?.sections.count ?? 0, 0)
    }
    
    // MARK: - Teleprompter State Logic Tests
    
    @MainActor
    func testTeleprompterTogglePlayPause() {
        let scripts = ScriptAPIService.mockScripts(for: GenerationRequest(inputType: .rawText, content: "Test", style: .casual))
        guard let mockScript = scripts.first else {
            XCTFail("Expected mock scripts to be non-empty")
            return
        }
        let vm = TeleprompterViewModel(script: mockScript)
        
        XCTAssertFalse(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertTrue(vm.isPlaying)
        vm.togglePlayPause()
        XCTAssertFalse(vm.isPlaying)
    }
}
