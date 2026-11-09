// swift-tools-version: 5.9
// Archery: the target archery game module (SwiftUI). Rules, physics and levels live in ArcheryEngine.
import PackageDescription

let package = Package(
    name: "Archery",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Archery", targets: ["Archery"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
        .package(path: "../../Packages/ArcheryEngine"),
    ],
    targets: [
        .target(
            name: "Archery",
            dependencies: [
                .product(name: "PlayKit", package: "PlayKit"),
                .product(name: "ArcheryEngine", package: "ArcheryEngine"),
            ]
        ),
    ]
)
