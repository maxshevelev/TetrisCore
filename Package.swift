// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "tetris",
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
            dependencies: ["Model", "ConsoleUI"]
        ),
    ]
)
