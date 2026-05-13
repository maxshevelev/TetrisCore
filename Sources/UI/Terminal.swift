// Terminal.swift - Terminal control and rendering

import Darwin
import Foundation

// MARK: - Terminal Colors

enum Color: String {
    case red = "\u{001B}[31m"
    case green = "\u{001B}[32m"
    case yellow = "\u{001B}[33m"
    case blue = "\u{001B}[34m"
    case magenta = "\u{001B}[35m"
    case cyan = "\u{001B}[36m"
    case orange = "\u{001B}[38;5;208m"
}

// MARK: - Terminal Control

struct Terminal {
    static let clear = "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    static let home = "\u{001B}[H"
    static let eraseDown = "\u{001B}[0J"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"

    static func getTerminalSize() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0 {
            return (rows: Int(w.ws_row), cols: Int(w.ws_col))
        }
        return (rows: 24, cols: 80)
    }

    static func cursorPosition(row: Int, col: Int) -> String {
        return "\u{001B}[\(row);\(col)H"
    }
}
