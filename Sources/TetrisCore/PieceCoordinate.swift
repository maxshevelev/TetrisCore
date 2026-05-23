// PieceCoordinate.swift - Grid coordinate for a piece block

/// A single coordinate within a piece, used for active and preview pieces.
/// Grid-absolute for pieceBlocks, preview-local (0-3) for nextPieceBlocks.
public struct PieceCoordinate: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}
