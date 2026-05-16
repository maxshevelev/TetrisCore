// Main.swift - Entry point: wires components and starts the game

import ConsoleUI

@main
struct Tetris {
    static func main() {
        let ui = ConsoleGameUI()
        ui.run()
    }
}
