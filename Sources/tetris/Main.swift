// Main.swift - Entry point: wires components and starts the game

import ArgumentParser
import ConsoleUI
import Foundation
import Model

@main
struct Tetris: AsyncParsableCommand {
    @Option(name: .shortAndLong, help: "Path to a log file for debug output.")
    var debug: String?

    func run() async throws {
        let logger: GameLogger
        if let path = debug {
            let url = URL(fileURLWithPath: path)
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                logger = GameLogger { message in
                    let timestamp = ISO8601DateFormatter().string(from: Date())
                    handle.write(Data("[\(timestamp)] \(message)\n".utf8))
                }
            } else {
                logger = GameLogger()
            }
        } else {
            logger = GameLogger()
        }

        let ui = ConsoleGameUI(logger: logger)
        await ui.run()
    }
}