// swift-tools-version: 5.9
// Runner: the endless runner game module (SwiftUI). The course and the rules live in RunnerEngine.
import PackageDescription

let package = Package(
    name: "Runner",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Runner", targets: ["Runner"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
        .package(path: "../../Packages/RunnerEngine"),
    ],
    targets: [
        .target(
            name: "Runner",
            dependencies: [
                .product(name: "PlayKit", package: "PlayKit"),
                .product(name: "RunnerEngine", package: "RunnerEngine"),
            ]
        ),
    ]
)
