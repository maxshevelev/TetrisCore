// Terminal.swift - Terminal control utilities

import Darwin

public struct Terminal {
    public static let clear = "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    public static let home = "\u{001B}[H"
    public static let eraseDown = "\u{001B}[0J"
    public static let hideCursor = "\u{001B}[?25l"
    public static let showCursor = "\u{001B}[?25h"
    public static let reset = "\u{001B}[0m"
    public static let bold = "\u{001B}[1m"

    public static func getTerminalSize() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0 {
            return (rows: Int(w.ws_row), cols: Int(w.ws_col))
        }
        return (rows: 24, cols: 80)
    }

    public static func cursorPosition(row: Int, col: Int) -> String {
        return "\u{001B}[\(row);\(col)H"
    }
}
