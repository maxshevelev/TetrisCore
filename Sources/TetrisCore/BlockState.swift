// BlockState.swift - Abstract block states for UI-agnostic game logic

import Foundation

/// Represents the state of a single cell in the game grid.
/// This enum is UI-agnostic - the renderer decides how to display each state.
public enum BlockState: Equatable {
    /// Empty cell with no block
    case empty

    /// Cell filled with a tetromino block of the specified color
    case filled(TetrominoColor)

    /// True if the cell contains a filled block
    public var isFilled: Bool {
        if case .filled = self { return true }
        return false
    }

    /// The color of the block, if any
    public var color: TetrominoColor? {
        if case .filled(let color) = self { return color }
        return nil
    }
}
