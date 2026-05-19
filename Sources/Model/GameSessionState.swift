// GameSessionState.swift - Immutable snapshot of game state for UI rendering

import Foundation

/// Single block position with color — fully immutable, safe to escape the actor.
public struct PieceBlock {
    public let x: Int
    public let y: Int
    public let color: TetrominoColor
}

public struct GameSessionState {
    public let grid: [[BlockState]]
    public let pieceBlocks: [PieceBlock]
    public let nextPieceBlocks: [PieceBlock]
    public let score: Int
    public let level: Int
    public let state: GameState
    public let topScores: [StoredScore]

    public init(
        grid: [[BlockState]],
        pieceBlocks: [PieceBlock],
        nextPieceBlocks: [PieceBlock],
        score: Int,
        level: Int,
        state: GameState,
        topScores: [StoredScore] = []
    ) {
        self.grid = grid
        self.pieceBlocks = pieceBlocks
        self.nextPieceBlocks = nextPieceBlocks
        self.score = score
        self.level = level
        self.state = state
        self.topScores = topScores
    }
}
