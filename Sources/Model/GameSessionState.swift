// GameSessionState.swift - Immutable snapshot of game state for UI rendering

import Foundation

public struct GameSessionState {
    public let grid: [[BlockState]]
    public let currentPiece: Tetromino?
    public let currentX: Int
    public let currentY: Int
    public let nextPiece: Tetromino?
    public let score: Int
    public let level: Int
    public let state: GameState
}
