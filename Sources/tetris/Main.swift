// Main.swift - Entry point: wires components and starts the game

import ConsoleUI
import Foundation
import Model

@main
struct Tetris {
    static func main() async {
        var logFile: String?
        let args = CommandLine.arguments
        if let index = args.firstIndex(of: "-d") {
            logFile = args.dropFirst(Int(index) + 1).first
        }

        let logger: GameLogger
        if let path = logFile,
           let url = URL(string: path)
        {
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