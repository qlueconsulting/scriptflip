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
    
    func testMockAPIReturnsCorrectScriptCount() {
        let request = GenerationRequest(
            inputType: .rawText,
            content: "Testing raw text input content for short video",
            style: .directResponse,
            outputCount: 3
        )
        
        let scripts = ScriptAPIService.mockScripts(for: request)
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
    
    // MARK: - Launch Purity Tests
    
    @MainActor
    func testLaunchInitializationIsPureAndNonBlocking() {
        // Verify ViewModel & Service initializers execute with zero side-effects
        let vm = ScriptGeneratorViewModel()
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.errorMessage)
        XCTAssertTrue(vm.generatedScripts.isEmpty)
        
        let subManager = SubscriptionManager.shared
        XCTAssertFalse(subManager.isPurchasing)
    }
    
    // MARK: - Environment & Serialization Tests
    
    func testAppEnvironmentEndpointResolution() {
        let endpoint = AppEnvironment.generateScriptsEndpoint
        XCTAssertEqual(endpoint, "https://tcgonpbwenimvilzquoz.supabase.co/functions/v1/generate-scripts")
        XCTAssertTrue(endpoint.hasPrefix("https://"))
        XCTAssertTrue(endpoint.contains("tcgonpbwenimvilzquoz.supabase.co"))
    }
    
    func testGenerationRequestInputTextKeySerialization() throws {
        let request = GenerationRequest(
            inputText: "Test input video content",
            scriptStyle: "Casual"
        )
        let data = try JSONEncoder().encode(request)
        let jsonString = String(data: data, encoding: .utf8) ?? ""
        
        XCTAssertTrue(jsonString.contains("\"inputText\":\"Test input video content\""))
        XCTAssertTrue(jsonString.contains("\"scriptStyle\":\"Casual\""))
    }
    
    // MARK: - ViewModel Early Return & Logging Tests
    
    @MainActor
    func testGenerateScriptsEmptyInputEarlyReturn() async {
        let vm = ScriptGeneratorViewModel()
        vm.inputText = "   "
        
        await vm.generateScripts()
        
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.showErrorAlert)
        XCTAssertEqual(vm.errorMessage, "Please enter a valid YouTube/Podcast URL or transcript text.")
        XCTAssertTrue(vm.generatedScripts.isEmpty)
    }
    
    func testDebugLogServiceBuffer() {
        DebugLogService.shared.clear()
        DebugLogService.shared.log("Test message 1")
        DebugLogService.shared.log("Test message 2")
        
        let logs = DebugLogService.shared.getLogs()
        XCTAssertEqual(logs.count, 2)
        XCTAssertTrue(logs[0].contains("Test message 1"))
        XCTAssertTrue(logs[1].contains("Test message 2"))
    }
    
    // MARK: - TestFlight & Tester Override Tests
    
    func testTestFlightOrDebugDetection() {
        let isTestFlight = SubscriptionManager.isTestFlightOrDebug
        #if DEBUG
        XCTAssertTrue(isTestFlight)
        #else
        XCTAssertNotNil(isTestFlight)
        #endif
    }
    
    func testTesterOverrideToggle() {
        let initial = SubscriptionManager.isTesterOverrideEnabled
        defer { SubscriptionManager.isTesterOverrideEnabled = initial }
        
        SubscriptionManager.isTesterOverrideEnabled = true
        XCTAssertTrue(SubscriptionManager.isTesterOverrideEnabled)
        SubscriptionManager.isTesterOverrideEnabled = false
        XCTAssertFalse(SubscriptionManager.isTesterOverrideEnabled)
    }
    
    @MainActor
    func testUnlimitedModeBypassesCreditLimitation() {
        let initial = SubscriptionManager.isTesterOverrideEnabled
        SubscriptionManager.isTesterOverrideEnabled = true
        defer { SubscriptionManager.isTesterOverrideEnabled = initial }
        
        let subManager = SubscriptionManager.shared
        XCTAssertTrue(subManager.isUnlimited)
        
        let vm = ScriptGeneratorViewModel()
        XCTAssertTrue(vm.canGenerateFree)
    }
    
    func testResetUsageClearsQuota() {
        let tracker = UsageTracker.shared
        tracker.incrementUsage()
        tracker.incrementUsage()
        tracker.incrementUsage()
        
        tracker.resetUsage()
        let reset = tracker.getUsage()
        XCTAssertEqual(reset.usedCount, 0)
        XCTAssertEqual(reset.remainingFreeGenerations, 3)
        XCTAssertFalse(reset.isLimitReached)
    }
}




