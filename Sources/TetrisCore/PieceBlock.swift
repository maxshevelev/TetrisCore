// PieceBlock.swift - Single block position with color

/// A single block within the active or preview piece.
/// Coordinates are grid-absolute for pieceBlocks and preview-local (0-3) for nextPieceBlocks.
public struct PieceBlock: Hashable, Sendable {
    public let x: Int
    public let y: Int
    public let color: TetrominoColor

    public init(x: Int, y: Int, color: TetrominoColor) {
        self.x = x
        self.y = y
        self.color = color
    }
}
