// swift-tools-version: 5.9
// Bubbles: the bubble shooter game module (SwiftUI). Rules and levels live in BubbleEngine.
import PackageDescription

let package = Package(
    name: "Bubbles",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Bubbles", targets: ["Bubbles"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
        .package(path: "../../Packages/BubbleEngine"),
    ],
    targets: [
        .target(
            name: "Bubbles",
            dependencies: [
                .product(name: "PlayKit", package: "PlayKit"),
                .product(name: "BubbleEngine", package: "BubbleEngine"),
            ]
        ),
    ]
)
