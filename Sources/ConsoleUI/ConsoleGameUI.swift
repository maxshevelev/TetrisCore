// ConsoleGameUI.swift - Facade integrating controller, renderer, and input handler

import Foundation
import Model
import os

public final class ConsoleGameUI: @unchecked Sendable {
    private var input: ConsoleInputHandler?
    private let logger: Logger
    private let playerName: String

    public init(logger: Logger = Logger(), playerName: String = defaultPlayerName()) {
        self.input = ConsoleInputHandler()
        self.logger = logger
        self.playerName = playerName
    }

    public func run(logLevel: LogLevel? = nil) async {
        print(Terminal.hideCursor)
        print(Terminal.clear)
        fflush(stdout)

        input?.start()

        let renderer = ConsoleRenderer(terminal: TerminalAdapter())
        var gameController: GameController?

        let doneSemaphore = DispatchSemaphore(value: 0)

        let scoreStorage = ScoreStorage()

        gameController = GameController(
            logger: logger,
            logLevel: logLevel,
            scoreStorage: scoreStorage,
            playerName: playerName,
            onRender: { state in
                let output = renderer.render(data: state)
                print(output, terminator: "")
                fflush(stdout)
            },
            onGameFinished: {
                doneSemaphore.signal()
            }
        )
        input?.setInputReceiver(gameController!)

        // Start/restart the game
        await gameController!.start()

        // Wait for game over using semaphore
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            DispatchQueue.global().async {
                doneSemaphore.wait()
                continuation.resume()
            }
        }

        // Clean up the old controller before restarting
        gameController = nil

        // Final cleanup
        input?.stop()
        input?.cleanup()
        input = nil
        print(Terminal.clear)
        print(Terminal.showCursor)
        fflush(stdout)
    }
}
