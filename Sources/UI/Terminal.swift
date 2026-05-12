import Darwin

struct Terminal {
    static let clear = "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    static let home = "\u{001B}[H"
    static let eraseDown = "\u{001B}[0J"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"

    static let cyan = "\u{001B}[36m"
    static let yellow = "\u{001B}[33m"
    static let magenta = "\u{001B}[35m"
    static let green = "\u{001B}[32m"
    static let red = "\u{001B}[31m"
    static let blue = "\u{001B}[34m"
    static let orange = "\u{001B}[38;5;208m"

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
