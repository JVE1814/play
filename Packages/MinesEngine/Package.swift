// swift-tools-version: 5.9
// MinesEngine: the boards, rules and solver of Mines.
// Imports only Foundation, so it builds and tests on any platform (including Linux).
import PackageDescription

let package = Package(
    name: "MinesEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MinesEngine", targets: ["MinesEngine"]),
    ],
    targets: [
        .target(name: "MinesEngine"),
        // Developer tool: generates many boards and prints how often the solver accepts one and how long it takes.
        .executableTarget(name: "mines-calibrate", dependencies: ["MinesEngine"]),
        .testTarget(name: "MinesEngineTests", dependencies: ["MinesEngine"]),
    ]
)
