// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tetris",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "TetrisCore", targets: ["TetrisCore"]),
        .library(name: "ConsoleUI", targets: ["ConsoleUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
    ],
    targets: [
        // TetrisCore: UI-agnostic game engine
        .target(
            name: "TetrisCore",
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // ConsoleUI: Console-based reference UI implementation (macOS only)
        .target(
            name: "ConsoleUI",
            dependencies: ["TetrisCore"],
            swiftSettings: [.enableExperimentalFeature("StrictConcurrency")]
        ),
        // Main executable
        .executableTarget(
            name: "tetris",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "TetrisCore", "ConsoleUI",
            ]
        ),
        // Tests
        .testTarget(
            name: "TetrisCoreTests",
            dependencies: ["TetrisCore"]
        ),
    ]
)
