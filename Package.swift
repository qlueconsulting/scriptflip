// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ScriptFlip",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ScriptFlip",
            targets: ["ScriptFlip"]
        ),
    ],
    dependencies: [
        // RevenueCat SDK for Subscription & Paywall management
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0"),
        // Supabase SDK for Edge Functions & Auth
        .package(url: "https://github.com/supabase/supabase-swift.git", "2.0.0"..<"2.25.0"),
        // XCTestDynamicOverlay pinned to pre-Swift 6 version
        .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay.git", "1.2.0"..<"1.4.0")
    ],
    targets: [
        .target(
            name: "ScriptFlip",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
                .product(name: "RevenueCatUI", package: "purchases-ios"),
                .product(name: "Supabase", package: "supabase-swift")
            ],
            path: "ScriptFlip"
        ),
        .testTarget(
            name: "ScriptFlipTests",
            dependencies: ["ScriptFlip"],
            path: "ScriptFlipTests"
        ),
    ]
)
