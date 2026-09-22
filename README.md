# ScriptFlip for iOS

[![iOS 17.0+](https://img.shields.io/badge/iOS-17.0%2B-blue.svg)](https://developer.apple.com/ios/)
[![Swift 5.10 / 6](https://img.shields.io/badge/Swift-5.10%20%2F%206-orange.svg)](https://swift.org)
[![SwiftUI](https://img.shields.io/badge/UI-SwiftUI-purple.svg)](https://developer.apple.com/xcode/swiftui/)
[![Xcode Cloud](https://img.shields.io/badge/CI%2FCD-Xcode%20Cloud-success.svg)](https://developer.apple.com/xcode-cloud/)

**ScriptFlip** is an AI-powered video script extraction, script generation, and studio teleprompter application built natively for iOS. It enables content creators, educators, entrepreneurs, and video teams to transform viral social media videos (TikTok, Instagram Reels, YouTube Shorts) or rough ideas into high-converting, teleprompter-ready scripts in seconds.

---

## Features

### 1. Smart Ingestion & Transcription
- **Social Video URL Extraction**: Ingest public video links from TikTok, Instagram Reels, and YouTube Shorts.
- **Automated Caption Parsing**: Extracts spoken transcripts, pacing, and hooks directly from source media.
- **Raw Text & Idea Ingestion**: Alternatively, input freeform bullet points, rough talking notes, or product descriptions.

### 2. AI-Powered Script Generation
- Transforms source material into 3-5 minute speaking scripts optimized for short-form retention.
- **5 Proven Creator Styles**:
  - **Viral Hook**: High-energy opening hook designed to stop the scroll, followed by rapid-fire value delivery.
  - **Storyteller**: Narrative arc building emotional connection, relatable tension, and memorable takeaways.
  - **Educator**: Clear, structured breakdown translating complex concepts into actionable steps.
  - **Sales Pitch**: Direct-response structure with problem identification, solution framing, and a compelling call-to-action.
  - **Trendsetter**: Fast-paced, modern vernacular tailored to trending social video formats.

### 3. Studio Teleprompter
- **Distraction-Free Teleprompter**: Clean, high-contrast display designed for studio recording and front-facing cameras.
- **Auto-Scroll Engine**: Fluid, variable-speed auto-scrolling with customizable Words-Per-Minute (WPM) controls.
- **Dynamic Font Scaling**: Real-time slider adjusting typography size for comfortable reading at any shooting distance.
- **Gesture Controls**: 1-tap pause/play, rewind to top, and elapsed speaking timer.
- **Mirroring / Prompter Flip**: Hardware flip mode supporting beam-splitter glass and professional teleprompter rigs.

### 4. Local Script History & Export
- Local, secure FIFO history retaining the most recent generated scripts.
- 1-tap script reloading into the generator or direct teleprompter launch.
- Copy to clipboard and native iOS system ShareSheet integration.

### 5. In-App Subscriptions & Quota Engine
- Real-time Apple StoreKit 2 entitlement resolution on-device.
- **Tier Structure**:
  - **Free Tier**: 3 scripts per month with standard generation.
  - **Pro Weekly**: 50 scripts per week ($4.99/wk) with priority generation.
  - **Pro Monthly**: 250 scripts per month ($19.99/mo) with maximum quota and feature access.
- Dynamic toolbar quota badging and gated upgrade paywalls with strict monthly precedence.

---

## Architecture & Tech Stack

```
                                  +-----------------------+
                                  |  iOS Client (SwiftUI) |
                                  +-----------+-----------+
                                              |
                     +------------------------+------------------------+
                     |                                                 |
                     v                                                 v
         +-----------------------+                         +-----------------------+
         |  Supabase Edge Funcs  |                         |    StoreKit 2 / RC    |
         |  (Deno / TypeScript)  |                         |  In-App Subscriptions |
         +-----------+-----------+                         +-----------------------+
                     |
                     v
         +-----------------------+
         | Claude 3.5 Sonnet /   |
         |        Haiku          |
         +-----------------------+
```

- **Client Architecture**: SwiftUI with `@Observable` state observation, strict `@MainActor` thread-safety, and Swift Concurrency (`async`/`await`).
- **Backend**: Supabase Edge Functions running on Deno / TypeScript calling Anthropic Claude 3.5 models.
- **IAP & Entitlements**: Apple StoreKit 2 `Transaction.currentEntitlements` for real-time on-device verification paired with RevenueCat SDK (`purchases-ios` 5.0+).
- **Continuous Integration**: Apple Xcode Cloud triggered via the GitHub `main` branch for automated builds, unit tests, and TestFlight deployment.

---

## Repository Structure

```
ScriptFlip/
├── App/
│   ├── AppDelegate.swift          # App lifecycle & RevenueCat configuration
│   ├── Environment.swift          # Runtime environment & backend endpoints
│   └── ScriptFlipApp.swift        # Main App entrypoint & WindowGroup
├── Models/
│   ├── GenerationRequest.swift    # DTOs for backend API communication
│   ├── Script.swift               # Core Script and ScriptSection models
│   ├── ScriptStyle.swift          # Script style enum (Viral Hook, Storyteller, etc.)
│   └── UserUsage.swift            # Quota models and tier limits
├── Services/
│   ├── SubscriptionManager.swift  # StoreKit 2 & RevenueCat entitlement engine
│   ├── UsageTracker.swift         # Local quota persistence & cadence tracking
│   ├── HistoryManager.swift       # Local script history storage (FIFO)
│   ├── ScriptAPIService.swift     # Supabase backend client & network layer
│   ├── DebugLogService.swift      # In-memory logging for diagnostics
│   └── KeychainService.swift      # Anonymous device identifier management
├── ViewModels/
│   ├── ScriptGeneratorViewModel.swift  # Generation flow, validation, and quota
│   └── TeleprompterViewModel.swift     # Teleprompter scroll animation & timer
├── Views/
│   ├── Generator/                 # Main generator screen & input modes
│   ├── Teleprompter/              # Studio teleprompter view
│   ├── Results/                   # Script result cards & section breakdown
│   ├── Paywall/                   # Subscription paywall & tier cards
│   ├── History/                   # Script history sheet
│   ├── About/                     # Legal disclosures, version & support
│   └── Splash/                    # Animated splash screen
├── ScriptFlipTests/               # XCTest suite for API, models, and quotas
└── ScriptFlipUITests/             # UI interaction test suite
```

---

## Requirements

- **iOS**: 17.0 or later
- **macOS**: Sonoma 14.0 or later (for development)
- **Xcode**: 15.4 or Xcode 16+
- **Swift**: 5.10 or Swift 6

---

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/qlueconsulting/scriptflip.git
   cd scriptflip
   ```

2. **Open the project**:
   Open `ScriptFlip.xcodeproj` in Xcode:
   ```bash
   open ScriptFlip.xcodeproj
   ```

3. **Resolve SPM Dependencies**:
   Xcode will automatically resolve the Swift Package Manager dependencies:
   - `purchases-ios` (RevenueCat SDK 5.0.0+)

4. **Build & Run**:
   Select an iOS Simulator (iPhone 15/16 Pro) or a connected physical device and press `Cmd + R`.

---

## Testing

The project includes an automated test suite covering networking, error handling, quota cadence transitions, teleprompter text cleaning, and entitlement resolution:

```bash
# Run unit tests via xcodebuild
xcodebuild test \
  -project ScriptFlip.xcodeproj \
  -scheme ScriptFlip \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest'
```

Alternatively, press `Cmd + U` inside Xcode to run all test targets.

---

## Legal & Compliance

- **Developer**: Qlue Consulting Inc.
- **Privacy Policy**: [ScriptFlip Privacy Policy](https://gist.github.com/qlueconsulting/dd318693733c41c5a20ae5e39d585985)
- **Terms of Use (EULA)**: [Apple Standard EULA](https://www.apple.com/legal/internet-services/itunes/dev/stdeula/)
- **Customer Support**: [ScriptFlip Support](https://gist.github.com/qlueconsulting/1b038663d0ea21b8ccda1623b7e67f97)
- **Export Compliance**: `ITSAppUsesNonExemptEncryption` is set to `<false/>` in `Info.plist`.

---

## License

© 2026 Qlue Consulting Inc. All rights reserved.