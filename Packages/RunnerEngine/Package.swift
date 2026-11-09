// swift-tools-version: 5.9
// RunnerEngine: the endless course, the runner's movement, collisions, coins and power-ups of Runner.
// Imports only Foundation, so it builds and tests on any platform (including Linux).
import PackageDescription

let package = Package(
    name: "RunnerEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RunnerEngine", targets: ["RunnerEngine"]),
    ],
    targets: [
        .target(name: "RunnerEngine"),
        // Developer tool: runs many courses with bots of different skill and prints how far they get.
        .executableTarget(name: "runner-calibrate", dependencies: ["RunnerEngine"]),
        .testTarget(name: "RunnerEngineTests", dependencies: ["RunnerEngine"]),
    ]
)
