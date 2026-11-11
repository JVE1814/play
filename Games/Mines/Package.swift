// swift-tools-version: 5.9
// Mines: the logic puzzle's game module (SwiftUI). Rules live in MinesEngine.
import PackageDescription

let package = Package(
    name: "Mines",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Mines", targets: ["Mines"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
        .package(path: "../../Packages/MinesEngine"),
    ],
    targets: [
        .target(
            name: "Mines",
            dependencies: [
                .product(name: "PlayKit", package: "PlayKit"),
                .product(name: "MinesEngine", package: "MinesEngine"),
            ]
        ),
    ]
)
