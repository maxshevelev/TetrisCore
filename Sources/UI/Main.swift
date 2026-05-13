// Main.swift - Game entry point with event-driven architecture

import Foundation

@main
struct Tetris {
    static func main() {
        let inputHandler = InputHandler()
        let game = TetrisGame()
        let renderer = GameRenderer()

        print(Terminal.hideCursor)
        print(Terminal.clear)

        // Main game loop - UI is driven by Model events
        while !game.gameOver {
            // Process input
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

            // Update game state with elapsed time
            let now = Date()
            game.update(0, now: now)

            // Render the current state
            let renderOutput = renderer.render(state: game.gameState)
            print(renderOutput, terminator: "")
            fflush(stdout)

            usleep(40000)
        }

        inputHandler.disableRawMode()
        print(Terminal.showCursor)
    }
}
