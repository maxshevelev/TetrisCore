import Foundation
import Model

/// Console color palette mapping tetromino colors to ANSI escape codes.
/// Also provides additional colors for other UI elements.
public enum ColorPalette: Sendable {
    case cyan
    case yellow
    case magenta
    case green
    case red
    case blue
    case orange

    /// ANSI escape code for this color
    public var ansiCode: String {
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

    /// Map a domain TetrominoColor to its console palette equivalent.
    public static func from(_ color: TetrominoColor) -> ColorPalette {
        switch color {
        case .cyan:    return .cyan
        case .yellow:  return .yellow
        case .magenta: return .magenta
        case .green:   return .green
        case .red:     return .red
        case .blue:    return .blue
        case .orange:  return .orange
        }
    }
}
