// swift-tools-version: 5.9
// TestGame: a deliberately tiny game used only by UI tests (debug builds) to prove that a new
// module plus one registry entry is all it takes to add a game.
import PackageDescription

let package = Package(
    name: "TestGame",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "TestGame", targets: ["TestGame"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
    ],
    targets: [
        .target(name: "TestGame", dependencies: [.product(name: "PlayKit", package: "PlayKit")]),
    ]
)
