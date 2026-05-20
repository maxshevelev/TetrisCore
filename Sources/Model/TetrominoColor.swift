// TetrominoColor.swift - Color enum for tetromino pieces

import Foundation

/// Represents the colors of tetromino pieces.
/// This is a UI-agnostic color definition; renderers convert to display format.
public enum TetrominoColor: Sendable {
    case cyan    // I piece
    case yellow  // O piece
    case magenta // T piece
    case green   // S piece
    case red     // Z piece
    case blue    // J piece
    case orange  // L piece
}
