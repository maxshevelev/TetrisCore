// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tetris",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
    ],
    targets: [
        // Model: UI-agnostic game logic
        .target(
            name: "Model"
        ),
        // ConsoleUI: Console-based UI implementation (depends on Model)
        .target(
            name: "ConsoleUI",
            dependencies: ["Model"]
        ),
        // Main executable
        .executableTarget(
            name: "tetris",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "Model", "ConsoleUI",
            ]
        ),
        // Tests
        .testTarget(
            name: "ModelTests",
            dependencies: ["Model"]
        ),
    ]
)
