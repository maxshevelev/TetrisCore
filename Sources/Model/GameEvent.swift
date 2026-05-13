// GameEvent.swift - Events published by TetrisGame

import Foundation

/// Events published by the game when state changes occur
enum GameEvent {
    /// A piece has been locked into the grid
    case pieceLocked
    /// One or more lines have been cleared
    case lineCleared(lines: Int, score: Int)
    /// A new piece has been spawned
    case pieceSpawned
    /// The game is over
    case gameOver
    /// Score has changed
    case scoreChanged(score: Int)
    /// Level has changed
    case levelChanged(level: Int)
    /// Current piece position changed
    case pieceMoved
    /// Current piece was rotated
    case pieceRotated
}
