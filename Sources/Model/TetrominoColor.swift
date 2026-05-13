// TetrominoColor.swift - Color enum for tetromino pieces

import Foundation

/// Represents the colors of tetromino pieces.
/// This is a UI-agnostic color definition; renderers convert to display format.
enum TetrominoColor {
    case cyan    // I piece
    case yellow  // O piece
    case magenta // T piece
    case green   // S piece
    case red     // Z piece
    case blue    // J piece
    case orange  // L piece

    /// ANSI escape code for console rendering
    var ansiCode: String {
        switch self {
        case .cyan:    return "\u{001B}[36m"
        case .yellow:  return "\u{001B}[33m"
        case .magenta: return "\u{001B}[35m"
        case .green:   return "\u{001B}[32m"
        case .red:     return "\u{001B}[31m"
        case .blue:    return "\u{001B}[34m"
        case .orange:  return "\u{001B}[38;5;208m"
        }
    }
}
