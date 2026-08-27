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
    
    func testTierSpecificQuotaCalculations() {
        let usage = UserUsage(usedCount: 2, proUsedThisWeek: 45, proUsedThisMonth: 200)
        
        // Free tier
        XCTAssertEqual(usage.remainingGenerations(for: .free), 1)
        XCTAssertFalse(usage.isLimitReached(for: .free))
        
        // Pro Weekly tier (50/week limit)
        XCTAssertEqual(usage.remainingGenerations(for: .proWeekly), 5)
        XCTAssertFalse(usage.isLimitReached(for: .proWeekly))
        
        // Pro Monthly tier (250/month limit)
        XCTAssertEqual(usage.remainingGenerations(for: .proMonthly), 50)
        XCTAssertFalse(usage.isLimitReached(for: .proMonthly))
        
        // Pro Weekly limit reached
        let weeklyMax = UserUsage(proUsedThisWeek: 50)
        XCTAssertEqual(weeklyMax.remainingGenerations(for: .proWeekly), 0)
        XCTAssertTrue(weeklyMax.isLimitReached(for: .proWeekly))
        
        // Pro Monthly limit reached
        let monthlyMax = UserUsage(proUsedThisMonth: 250)
        XCTAssertEqual(monthlyMax.remainingGenerations(for: .proMonthly), 0)
        XCTAssertTrue(monthlyMax.isLimitReached(for: .proMonthly))
    }
    
    func testUsageTrackerIncrementByTier() {
        let tracker = UsageTracker.shared
        tracker.resetUsage()
        
        let freeInc = tracker.incrementUsage(tier: .free)
        XCTAssertEqual(freeInc.usedCount, 1)
        XCTAssertEqual(freeInc.proUsedThisWeek, 0)
        XCTAssertEqual(freeInc.proUsedThisMonth, 0)
        
        let weeklyInc = tracker.incrementUsage(tier: .proWeekly)
        XCTAssertEqual(weeklyInc.usedCount, 1)
        XCTAssertEqual(weeklyInc.proUsedThisWeek, 1)
        XCTAssertEqual(weeklyInc.proUsedThisMonth, 0)
        
        let monthlyInc = tracker.incrementUsage(tier: .proMonthly)
        XCTAssertEqual(monthlyInc.usedCount, 1)
        XCTAssertEqual(monthlyInc.proUsedThisWeek, 1)
        XCTAssertEqual(monthlyInc.proUsedThisMonth, 1)
        
    func testPublicGMReleaseConfigurationSettings() {
        // Verify Live Public API Configuration
        let key = AppEnvironment.revenueCatAPIKey
        XCTAssertFalse(key.isEmpty)
        XCTAssertTrue(key.starts(with: "appl_") || key.starts(with: "test_"))
        
        // Verify Tier Quotas conform to App Store product requirements
        XCTAssertEqual(UserUsage.freeMonthlyLimit, 3)
        XCTAssertEqual(UserUsage.proWeeklyLimit, 50)
        XCTAssertEqual(UserUsage.proMonthlyLimit, 250)
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
    
    func testUniversalScriptPlatformInitialization() {
        let dto = GeneratedScriptDTO(
            hook: "Universal Hook for all platforms",
            body: "Universal Body content",
            visualCue: "Direct camera zoom",
            cta: "Save and share"
        )
        let script = Script(dto: dto, index: 1, style: .casual)
        
        XCTAssertEqual(script.targetPlatform, .universal)
        XCTAssertEqual(script.targetPlatform.rawValue, "Universal (TikTok, Reels, Shorts)")
        XCTAssertEqual(script.targetPlatform.iconName, "sparkles.rectangle.stack.fill")
        XCTAssertEqual(script.title, "Universal Script: \(ScriptStyle.casual.rawValue) Angle")
        XCTAssertEqual(script.sections.count, 3)
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
    
    func testExportComplianceNonExemptEncryptionDeclaration() {
        // Verify ITSAppUsesNonExemptEncryption is configured for TestFlight automation
        guard let infoPlistPath = Bundle.main.path(forResource: "Info", ofType: "plist") ?? Bundle(for: type(of: self)).path(forResource: "Info", ofType: "plist"),
              let dict = NSDictionary(contentsOfFile: infoPlistPath) else {
            // If running in test host where bundle dictionary is directly in main bundle:
            if let usesNonExempt = Bundle.main.object(forInfoDictionaryKey: "ITSAppUsesNonExemptEncryption") as? Bool {
                XCTAssertFalse(usesNonExempt)
            }
            return
        }
        if let usesNonExempt = dict["ITSAppUsesNonExemptEncryption"] as? Bool {
            XCTAssertFalse(usesNonExempt)
        }
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
    
    @MainActor
    func testTestFlightOrDebugDetection() {
        let isTestFlight = SubscriptionManager.isTestFlightOrDebug
        #if DEBUG
        XCTAssertTrue(isTestFlight)
        #else
        XCTAssertNotNil(isTestFlight)
        #endif
    }
    
    @MainActor
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
    
    @MainActor
    func testMissingCaptionsAlertTrigger() async {
        final class MockCaptionsFailAPIService: ScriptAPIServiceProtocol, @unchecked Sendable {
            func generateScripts(request: GenerationRequest) async throws -> [Script] {
                throw ScriptAPIError.badRequest(statusCode: 400, responseBody: "{\"error\":\"No captions found for this YouTube video. Please paste the transcript or summary text manually.\"}")
            }
            func getDiagnostics() -> NetworkDiagnosticInfo {
                NetworkDiagnosticInfo()
            }
        }
        
        let vm = ScriptGeneratorViewModel(apiService: MockCaptionsFailAPIService())
        vm.inputText = "https://youtube.com/watch?v=dQw4w9WgXcQ"
        
        await vm.generateScripts()
        
        XCTAssertFalse(vm.isLoading)
        XCTAssertTrue(vm.showMissingCaptionsAlert)
        XCTAssertEqual(vm.errorMessage, "No captions found for this YouTube video. Please paste the transcript or summary text manually.")
    }
    
    // MARK: - HistoryManager & Universal Script DTO Tests
    
    func testHistoryManagerStrictCapAtFive() {
        let history = HistoryManager(userDefaults: .standard, storageKey: "test_scriptflip_history_\(UUID().uuidString)")
        history.clearHistory()
        
        for i in 1...8 {
            let script = Script(
                title: "Script Test \(i)",
                style: .casual,
                sections: [
                    ScriptSection(timeRange: "0:00 - 0:03", sectionType: .hook, spokenText: "Hook \(i)", visualCue: "Cue \(i)"),
                    ScriptSection(timeRange: "0:03 - 0:25", sectionType: .body, spokenText: "Body \(i)", visualCue: "Cue \(i)"),
                    ScriptSection(timeRange: "0:25 - 0:30", sectionType: .callToAction, spokenText: "CTA \(i)", visualCue: "Cue \(i)")
                ],
                keyTakeaway: "Tip \(i)"
            )
            history.addScript(script)
        }
        
        let saved = history.getHistory()
        XCTAssertEqual(saved.count, 5, "History must strictly cap at 5 items")
        XCTAssertEqual(saved.first?.title, "Script Test 8", "Newest item must be first in history (FIFO drop oldest)")
        XCTAssertEqual(saved.last?.title, "Script Test 4", "Oldest item retained should be Script Test 4")
        
        history.clearHistory()
        XCTAssertTrue(history.getHistory().isEmpty)
    }
    
    func testUniversalScriptResponseJSONDecoding() throws {
        let json = """
        {
          "script": {
            "title": "3 Habits That Skyrocketed My Focus",
            "hook": "Stop waking up and checking your phone immediately.",
            "body": "Your brain is in theta state. When you scroll social media, you flood it with dopamine debt. Instead, drink 16oz water and get 5 mins morning sunlight.",
            "callToAction": "Save this video and try it tomorrow morning!",
            "estimatedDuration": "35s",
            "visualCues": ["Close-up phone with notifications", "Drinking tall glass of water", "Sunlight window smile"]
          },
          "activeModel": "claude-sonnet-4-6"
        }
        """.data(using: .utf8)!
        
        let decoded = try JSONDecoder().decode(GenerationResponse.self, from: json)
        XCTAssertNotNil(decoded.script)
        XCTAssertEqual(decoded.script?.title, "3 Habits That Skyrocketed My Focus")
        XCTAssertEqual(decoded.script?.hook, "Stop waking up and checking your phone immediately.")
        XCTAssertEqual(decoded.script?.estimatedDuration, "35s")
        XCTAssertEqual(decoded.script?.visualCues?.count, 3)
        
        guard let dto = decoded.script else {
            XCTFail("Expected non-nil script DTO")
            return
        }
        let script = Script(dto: dto, index: 1, style: .educational)
        XCTAssertEqual(script.title, "3 Habits That Skyrocketed My Focus")
        XCTAssertEqual(script.sections.count, 3)
        XCTAssertEqual(script.sections[0].spokenText, "Stop waking up and checking your phone immediately.")
        XCTAssertEqual(script.sections[0].visualCue, "Close-up phone with notifications")
    }
    
    @MainActor
    func testTeleprompterViewModelControlsRange() {
        let script = Script(
            title: "Controls Test",
            style: .casual,
            sections: [
                ScriptSection(timeRange: "0:00 - 0:03", sectionType: .hook, spokenText: "Test hook", visualCue: "Test cue")
            ],
            keyTakeaway: "Takeaway"
        )
        let vm = TeleprompterViewModel(script: script)
        
        XCTAssertEqual(vm.scrollSpeed, 35)
        XCTAssertEqual(vm.fontSize, 32)
        
        vm.scrollSpeed = 50
        vm.fontSize = 40
        XCTAssertEqual(vm.scrollSpeed, 50)
        XCTAssertEqual(vm.fontSize, 40)
        
        vm.resetPrompter()
        XCTAssertFalse(vm.isPlaying)
        XCTAssertEqual(vm.scrollOffset, 0)
    }
}




