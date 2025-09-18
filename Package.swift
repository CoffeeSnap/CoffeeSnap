// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoffeeSnapAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .executable(name: "CoffeeSnapAI", targets: ["CoffeeSnapAI"])
    ],
    dependencies: [
        .package(url: "https://github.com/stephencelis/SQLite.swift.git", from: "0.14.1"),
        .package(url: "https://github.com/apple/swift-algorithms", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "CoffeeSnapAI",
            dependencies: [
                .product(name: "SQLite", package: "SQLite.swift"),
                .product(name: "Algorithms", package: "swift-algorithms")
            ],
            path: "CoffeeSnapAI"
        ),
        .testTarget(
            name: "CoffeeSnapAITests",
            dependencies: ["CoffeeSnapAI"],
            path: "Tests"
        )
    ]
)
