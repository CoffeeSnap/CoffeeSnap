// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CoffeeSnapAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "CoffeeSnapAI", targets: ["CoffeeSnapAI"])
    ],
    targets: [
        .target(
            name: "CoffeeSnapAI",
            path: "CoffeeSnapAI",
            exclude: [
                "Assets.xcassets",
                "CoffeeSnapAIApp.swift",
                "ContentView.swift",
                "Info.plist",
                "PrivacyInfo.xcprivacy",
                "Preview Content",
                "Services/CameraService.swift",
                "Services/MLService.swift",
                "Utils",
                "Views"
            ],
            sources: [
                "Models/CoffeeModel.swift",
                "Models/TasteMemoryModel.swift",
                "Services/CoffeeEmbeddingService.swift",
                "Services/TasteMemoryEngine.swift",
                "Services/VisualEmbeddingService.swift",
                "Services/VectorDatabaseService.swift",
                "ViewModels/CoffeeStore.swift"
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "CoffeeSnapAITests",
            dependencies: ["CoffeeSnapAI"],
            path: "Tests",
            sources: [
                "CoffeeSnapAITests/Integration/CoffeeStoreIntegrationTests.swift",
                "CoffeeSnapAITests/Integration/VectorDatabaseIntegrationTests.swift"
            ]
        )
    ]
)
