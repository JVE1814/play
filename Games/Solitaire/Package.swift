// swift-tools-version: 5.9
// Solitaire: the Klondike game module (SwiftUI). Rules live in KlondikeEngine.
import PackageDescription

let package = Package(
    name: "Solitaire",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "Solitaire", targets: ["Solitaire"]),
    ],
    dependencies: [
        .package(path: "../../Packages/PlayKit"),
        .package(path: "../../Packages/KlondikeEngine"),
    ],
    targets: [
        .target(
            name: "Solitaire",
            dependencies: [
                .product(name: "PlayKit", package: "PlayKit"),
                .product(name: "KlondikeEngine", package: "KlondikeEngine"),
            ],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
    ]
)
