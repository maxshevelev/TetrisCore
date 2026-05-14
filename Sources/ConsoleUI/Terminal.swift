// Terminal.swift - Console UI module (Terminal + Renderer + Input)

import Darwin
import Foundation
import Model

// MARK: - Terminal Control

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

// MARK: - TerminalOperations Protocol

public protocol TerminalOperations {
    var clear: String { get }
    var home: String { get }
    var eraseDown: String { get }
    var hideCursor: String { get }
    var showCursor: String { get }
    var reset: String { get }
    var bold: String { get }
    func getTerminalSize() -> (rows: Int, cols: Int)
    func cursorPosition(row: Int, col: Int) -> String
}

public struct TerminalAdapter: TerminalOperations {
    public func getTerminalSize() -> (rows: Int, cols: Int) {
        Terminal.getTerminalSize()
    }

    public func cursorPosition(row: Int, col: Int) -> String {
        Terminal.cursorPosition(row: row, col: col)
    }

    public var clear: String { Terminal.clear }
    public var home: String { Terminal.home }
    public var eraseDown: String { Terminal.eraseDown }
    public var hideCursor: String { Terminal.hideCursor }
    public var showCursor: String { Terminal.showCursor }
    public var reset: String { Terminal.reset }
    public var bold: String { Terminal.bold }

    public init() {}
}

// MARK: - GameInput Protocol

public protocol GameInput {
    func start()
    func stop()
    func nextKey() -> KeyAction?
}

public enum KeyAction {
    case left
    case right
    case rotate
    case drop
    case pause
    case quit
}

// MARK: - ConsoleRenderer

public protocol GameRenderer {
    func render(state: GameSessionState) -> String
}

public struct ConsoleRenderer: GameRenderer {
    private let terminal: TerminalOperations

    public init(terminal: TerminalOperations) {
        self.terminal = terminal
    }

    public func render(state: GameSessionState) -> String {
        let size = terminal.getTerminalSize()
        let width = state.grid.first?.count ?? 10
        let height = state.grid.count
        let boardWidth = width * 2 + 2
        let boardHeight = height + 2
        let padLeft = max(0, (size.cols - boardWidth) / 2)
        let padTop = max(0, (size.rows - boardHeight - 4) / 2)
        let startRow = padTop + 1
        let startCol = padLeft + 1
        let nextCol = max(1, startCol - 12)
        let dropInterval = max(0.15, 0.8 - Double(state.level - 1) * 0.06)

        var output = terminal.home + terminal.eraseDown

        // Draw next piece preview
        if let next = state.nextPiece {
            output += terminal.cursorPosition(row: startRow, col: nextCol)
            output += terminal.bold + "Next:" + terminal.reset
            for y in 0..<4 {
                output += terminal.cursorPosition(row: startRow + y + 1, col: nextCol)
                for x in 0..<4 {
                    var hasBlock = false
                    for (px, py) in next.getAbsoluteCoordinates(xOffset: 0, yOffset: 0) {
                        if px == x && py == y {
                            hasBlock = true
                            break
                        }
                    }
                    if hasBlock {
                        output += next.shape.blockColor.ansiCode + "██" + terminal.reset
                    } else {
                        output += "  "
                    }
                }
            }
        }

        output += terminal.cursorPosition(row: startRow, col: startCol)
        output += terminal.bold + "╔" + String(repeating: "═", count: width * 2) + "╗" + terminal.reset

        for y in 0..<height {
            output += terminal.cursorPosition(row: startRow + y + 1, col: startCol)
            output += terminal.bold + "║" + terminal.reset
            for x in 0..<width {
                let currentCell = state.grid[y][x]
                var color: TetrominoColor?

                // Check if grid cell is filled
                if currentCell.isFilled {
                    color = currentCell.color
                } else if let piece = state.currentPiece {
                    // Check if current piece covers this cell
                    for (px, py) in piece.getAbsoluteCoordinates(xOffset: state.currentX, yOffset: state.currentY) {
                        if px == x && py == y {
                            color = piece.shape.blockColor
                            break
                        }
                    }
                }

                if let color = color {
                    output += color.ansiCode + "██" + terminal.reset
                } else {
                    output += "· "
                }
            }
            output += terminal.bold + "║" + terminal.reset
        }

        output += terminal.cursorPosition(row: startRow + height + 1, col: startCol)
        output += terminal.bold + "╚" + String(repeating: "═", count: width * 2) + "╝" + terminal.reset

        func centerColumn(for text: String) -> Int {
            return startCol + max(0, (boardWidth - text.count) / 2)
        }

        let scoreText = "Score: \(state.score)  Level: \(state.level)"
        let controlsText = "Controls: j=left  k=rotate  l=right  SPACE=drop  q=quit"
        let statusText = state.paused ? "PAUSED - Press ESC to resume" : "Drop: \(String(format: "%.2fs", dropInterval))"

        output += terminal.cursorPosition(row: startRow + height + 3, col: centerColumn(for: scoreText))
        output += "Score: " + terminal.bold + String(state.score) + terminal.reset + "  Level: " + terminal.bold + String(state.level) + terminal.reset

        output += terminal.cursorPosition(row: startRow + height + 4, col: centerColumn(for: controlsText))
        output += controlsText

        output += terminal.cursorPosition(row: startRow + height + 5, col: centerColumn(for: statusText))
        if state.paused {
            output += terminal.bold + TetrominoColor.red.ansiCode + statusText + terminal.reset
        } else {
            output += statusText
        }

        return output
    }
}

// MARK: - ConsoleInputHandler

public class ConsoleInputHandler: GameInput {
    private let inputQueue = DispatchQueue(label: "input.queue")
    private var originalTermios = termios()
    private var lastKey: KeyAction?
    private var running = false

    public init() {
        enableRawMode()
    }

    deinit {
        disableRawMode()
    }

    public func start() {
        running = true
        inputQueue.async { [weak self] in
            guard let self = self else { return }
            while self.running {
                var byte: UInt8 = 0
                let n = read(STDIN_FILENO, &byte, 1)
                if n == 1 {
                    self.processByte(byte)
                }
                usleep(10000)
            }
        }
    }

    public func stop() {
        running = false
    }

    public func nextKey() -> KeyAction? {
        let key = lastKey
        lastKey = nil
        return key
    }

    private func processByte(_ byte: UInt8) {
        let scalar = UnicodeScalar(byte)
        let char = Character(scalar)

        switch char {
        case "j":
            lastKey = .left
        case "l":
            lastKey = .right
        case "k":
            lastKey = .rotate
        case " ":
            lastKey = .drop
        case "\u{1b}":
            lastKey = .pause
        case "q":
            lastKey = .quit
        default:
            break
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL) | UInt(BRKINT) | UInt(INPCK) | UInt(ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }
}
