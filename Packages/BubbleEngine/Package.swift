// swift-tools-version: 5.9
// BubbleEngine: rules, physics and level generation for the Bubbles game.
// Imports only Foundation, so it builds and tests on any platform (including Linux).
import PackageDescription

let package = Package(
    name: "BubbleEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "BubbleEngine", targets: ["BubbleEngine"]),
    ],
    targets: [
        .target(name: "BubbleEngine"),
        // Developer tool: plays every level with the bot and prints LevelPar.generated.swift.
        .executableTarget(name: "bubble-par", dependencies: ["BubbleEngine"]),
        .testTarget(name: "BubbleEngineTests", dependencies: ["BubbleEngine"]),
    ]
)
