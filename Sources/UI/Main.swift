// Main.swift - Game entry point

import Foundation

@main
struct Tetris {
    static func main() {
        let inputHandler = InputHandler()
        let game = TetrisGame()

        print(Terminal.hideCursor)
        print(Terminal.clear)

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
                game.update()
            }
            game.render()
            usleep(40000)
        }

        inputHandler.disableRawMode()
        print(Terminal.showCursor)
    }
}
