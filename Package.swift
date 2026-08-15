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
        .package(url: "https://github.com/RevenueCat/purchases-ios.git", from: "5.0.0")
    ],
    targets: [
        .target(
            name: "ScriptFlip",
            dependencies: [
                .product(name: "RevenueCat", package: "purchases-ios"),
                .product(name: "RevenueCatUI", package: "purchases-ios")
            ],
            path: "ScriptFlip",
            exclude: ["Info.plist"]
        ),
        .testTarget(
            name: "ScriptFlipTests",
            dependencies: ["ScriptFlip"],
            path: "ScriptFlipTests"
        ),
    ]
)
