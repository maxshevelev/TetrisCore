// GameEvent.swift - Diff-style update events for the tick stream

import Foundation

/// A single changed value on the tick stream.
/// Multiple events are yielded as a `Set` each tick — only changed fields appear.
public enum GameEvent: Hashable, Sendable {
    case grid([[BlockState]])
    case pieceBlocks([PieceBlock], hardDropDuration: TimeInterval?)
    case nextPieceBlocks([PieceBlock])
    case score(Int)
    case level(Int)
    case linesCleared(Int, clearedRows: Set<Int>, animationDuration: TimeInterval)
    case state(GameDisplayState)
    case topScores([StoredScore])
    case playerName(String)
}
