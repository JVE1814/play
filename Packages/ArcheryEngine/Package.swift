// swift-tools-version: 5.9
// ArcheryEngine: target faces, scoring, wind, sway, moving targets and the 30 levels of Archery.
// Imports only Foundation, so it builds and tests on any platform (including Linux).
import PackageDescription

let package = Package(
    name: "ArcheryEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ArcheryEngine", targets: ["ArcheryEngine"]),
    ],
    targets: [
        .target(name: "ArcheryEngine"),
        // Developer tool: plays every level with the expert and novice bots and prints how they score.
        .executableTarget(name: "archery-calibrate", dependencies: ["ArcheryEngine"]),
        .testTarget(name: "ArcheryEngineTests", dependencies: ["ArcheryEngine"]),
    ]
)
