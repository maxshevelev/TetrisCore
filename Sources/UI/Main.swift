// Main.swift - Game entry point with controller logic

import Foundation

@main
struct Tetris {
    static func main() {
        let inputHandler = InputHandler()
        let game = TetrisGame()
        let renderer = GameRenderer()

        let baseDropInterval: TimeInterval = 0.8

        print(Terminal.hideCursor)
        print(Terminal.clear)

        var lastDropTime = Date()

        while !game.gameOver {
            if let input = inputHandler.getInput() {
                switch input {
                case "j": game.moveLeft()
                case "k": game.rotatePiece()
                case "l": game.moveRight()
                case " ": game.hardDrop()
                case "\u{1b}": game.paused.toggle()
                case "q": game.gameOver = true
                default: break
                }
            }

            if !game.paused {
                let now = Date()
                let dropInterval = max(0.15, baseDropInterval - Double(game.level - 1) * 0.06)

                // Auto drop based on gravity interval
                if now.timeIntervalSince(lastDropTime) > dropInterval {
                    game.moveDown()
                    lastDropTime = now
                }

                // Handle piece locking
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

            let renderOutput = renderer.render(
                grid: game.grid,
                currentPiece: game.currentPiece,
                currentX: game.pieceX,
                currentY: game.pieceY,
                nextPiece: game.nextPiece,
                score: game.score,
                level: game.level,
                dropInterval: max(0.15, baseDropInterval - Double(game.level - 1) * 0.06),
                paused: game.paused,
                gameOver: game.gameOver
            )
            print(renderOutput, terminator: "")
            fflush(stdout)

            usleep(40000)
        }

        inputHandler.disableRawMode()
        print(Terminal.showCursor)
    }
}
