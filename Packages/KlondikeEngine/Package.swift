// swift-tools-version: 5.9
// KlondikeEngine: the Klondike Solitaire rules engine.
// Pure value types that import only Foundation, so they can be tested on any
// platform (including Linux) and reused by any front end.
import PackageDescription

let package = Package(
    name: "KlondikeEngine",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "KlondikeEngine", targets: ["KlondikeEngine"]),
    ],
    targets: [
        .target(name: "KlondikeEngine"),
        .testTarget(name: "KlondikeEngineTests", dependencies: ["KlondikeEngine"]),
    ]
)
