// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoffeeSnapAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "CoffeeSnapAI",
            targets: ["CoffeeSnapAI"]),
    ],
    dependencies: [
        // Add any third-party dependencies here if needed
        // Example:
        // .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0"),
    ],
    targets: [
        .target(
            name: "CoffeeSnapAI",
            dependencies: []),
        .testTarget(
            name: "CoffeeSnapAITests",
            dependencies: ["CoffeeSnapAI"]),
    ]
)
