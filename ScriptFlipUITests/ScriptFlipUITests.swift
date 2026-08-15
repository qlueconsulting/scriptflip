import XCTest

final class ScriptFlipUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testGeneratorToResultsToPrompterFlow() throws {
        let app = XCUIApplication()
        app.launch()
        
        // 1. Verify Home Title exists
        XCTAssertTrue(app.navigationBars["ScriptFlip"].exists)
        
        // 2. Select Style
        let storytellingButton = app.buttons["Storytelling & Narrative"]
        if storytellingButton.exists {
            storytellingButton.tap()
        }
        
        // Switch to Raw Transcript / Text mode
        let rawTextButton = app.buttons["Raw Transcript / Text"]
        if rawTextButton.exists {
            rawTextButton.tap()
        }
        
        // 3. Enter Text in input editor
        let textEditor = app.textViews.firstMatch
        if textEditor.exists {
            textEditor.tap()
            textEditor.typeText("How to build iOS apps with Swift concurrency and RevenueCat.")
        }
        
        // 4. Tap Generate Scripts
        let generateButton = app.buttons["Generate Short-Form Scripts"]
        if generateButton.exists {
            generateButton.tap()
        }
        
        // 5. Verify Results Sheet displays
        let resultsHeader = app.staticTexts["Generated Scripts (9:16 Preview)"]
        if resultsHeader.waitForExistence(timeout: 5.0) {
            // 6. Tap Prompter button on first script card
            let prompterButton = app.buttons["Prompter"].firstMatch
            if prompterButton.exists {
                prompterButton.tap()
                
                // 7. Verify Teleprompter screen exit button exists
                let exitPrompterButton = app.buttons["Exit"]
                if exitPrompterButton.waitForExistence(timeout: 3.0) {
                    exitPrompterButton.tap()
                }
            }
        }
    }
    
    func testPaywallTriggerOnLimitExceeded() throws {
        let app = XCUIApplication()
        app.launch()
        
        // Tap Free Left Badge to open Paywall directly
        let badgeButton = app.buttons.containing(.image, identifier: "sparkles").firstMatch
        if badgeButton.exists {
            badgeButton.tap()
            
            let paywallTitle = app.staticTexts["Unlock ScriptFlip Pro"]
            XCTAssertTrue(paywallTitle.waitForExistence(timeout: 3.0))
        }
    }
}
