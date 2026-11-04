// swift-tools-version: 5.9
// PlayKit: everything games share. The GameModule protocol, design tokens and
// components, save/resume, per-game statistics, settings and feedback.
import PackageDescription

let package = Package(
    name: "PlayKit",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "PlayKit", targets: ["PlayKit"]),
    ],
    targets: [
        .target(
            name: "PlayKit",
            resources: [.process("Resources")],
            swiftSettings: [.define("DEBUG", .when(configuration: .debug))]
        ),
    ]
)
