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
    public let linesCleared: Int
    public let state: GameDisplayState
    public let topScores: [StoredScore]
    public let playerName: String

    public init(
        grid: [[BlockState]],
        pieceBlocks: [PieceBlock],
        nextPieceBlocks: [PieceBlock],
        score: Int,
        level: Int,
        linesCleared: Int,
        state: GameDisplayState,
        topScores: [StoredScore] = [],
        playerName: String = defaultPlayerName()
    ) {
        self.grid = grid
        self.pieceBlocks = pieceBlocks
        self.nextPieceBlocks = nextPieceBlocks
        self.score = score
        self.level = level
        self.linesCleared = linesCleared
        self.state = state
        self.topScores = topScores
        self.playerName = playerName
    }
}
