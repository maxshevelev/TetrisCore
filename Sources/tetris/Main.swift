// Main.swift - Entry point that wires everything together

import Foundation
import Model
import ConsoleUI

@main
struct Tetris {
    static func main() {
        let game = TetrisGame()
        let input = ConsoleInputHandler()
        let renderer = ConsoleRenderer(terminal: TerminalAdapter())

        // Start input
        input.start()

        // Print initial render
        print(Terminal.hideCursor)
        defer {
            input.stop()
            print(Terminal.showCursor)
        }

        print(Terminal.clear)
        print(renderer.render(state: game.gameState), terminator: "")
        fflush(stdout)

        let baseDropInterval: TimeInterval = 0.8
        var lastDropTime = Date()

        // Game loop
        while !game.gameOver {
            // Process input
            while let key = input.nextKey() {
                switch key {
                case .left: game.moveLeft()
                case .right: game.moveRight()
                case .rotate: game.rotatePiece()
                case .drop: game.hardDrop()
                case .pause: game.paused.toggle()
                case .quit: game.gameOver = true
                }
            }

            // Update game state
            if !game.paused {
                let now = Date()
                let dropInterval = max(0.15, baseDropInterval - Double(game.level - 1) * 0.06)

                // Auto-drop
                if now.timeIntervalSince(lastDropTime) >= dropInterval {
                    game.moveDown()
                    lastDropTime = now
                }

                // Check for piece lock
                if game.shouldLock(now) {
                    if game.currentPiece != nil {
                        if game.canMoveDown() {
                            game.moveDown()
                            lastDropTime = now
                        } else {
                            game.lockPiece()
                            game.clearLines()
                            game.spawnNewPieceAndClear()
                            lastDropTime = now
                        }
                    }
                }
            }

            // Render
            print(renderer.render(state: game.gameState), terminator: "")
            fflush(stdout)

            usleep(40000)  // 25 FPS target
        }
    }
}
