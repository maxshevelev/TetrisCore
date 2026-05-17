// Main.swift - Entry point: wires components and starts the game

import ConsoleUI

@main
struct Tetris {
    static func main() async {
        let ui = ConsoleGameUI()
        await ui.run()
    }
}
