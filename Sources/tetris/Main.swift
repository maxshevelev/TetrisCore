// Main.swift - Entry point: wires components and starts the game

import ArgumentParser
import ConsoleUI
import Foundation
import TetrisCore
import os

@main
struct Tetris: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Logging level: debug, info, notice, error, or fault.")
    var debug: String?

    @Option(name: .shortAndLong, help: "Player name for the game session.")
    var user: String?

    func run() async throws {
        let logLevel: LogLevel?
        if let raw = debug {
            logLevel = LogLevel(rawValue: raw.lowercased())
        } else {
            logLevel = nil
        }

        let logger = Logger(subsystem: "com.maxik.tetris", category: "game")
        let ui = ConsoleGameUI(logger: logger, playerName: user)
        await ui.run(logLevel: logLevel)
    }
}
