// GameRenderer.swift - UI rendering for tetris game state

import Foundation

/// Protocol for terminal operations - enables dependency injection for testing
protocol TerminalProtocol {
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

/// Concrete terminal implementation
struct TerminalAdapter: TerminalProtocol {
    func getTerminalSize() -> (rows: Int, cols: Int) {
        Terminal.getTerminalSize()
    }

    func cursorPosition(row: Int, col: Int) -> String {
        Terminal.cursorPosition(row: row, col: col)
    }

    var clear: String { Terminal.clear }
    var home: String { Terminal.home }
    var eraseDown: String { Terminal.eraseDown }
    var hideCursor: String { Terminal.hideCursor }
    var showCursor: String { Terminal.showCursor }
    var reset: String { Terminal.reset }
    var bold: String { Terminal.bold }
}

/// Renders game state to a string for display
struct GameRenderer {
    private let terminal: TerminalProtocol

    /// Creates a renderer with the given terminal adapter
    /// - Parameter terminal: Terminal protocol for output operations
    init(terminal: TerminalProtocol = TerminalAdapter()) {
        self.terminal = terminal
    }

    /// Renders the complete game state to a display string
    /// - Parameters:
    ///   - grid: The game grid
    ///   - currentPiece: The currently active piece
    ///   - currentX: X position of current piece
    ///   - currentY: Y position of current piece
    ///   - nextPiece: The next piece to spawn
    ///   - score: Current score
    ///   - level: Current level
    ///   - dropInterval: Current drop interval
    ///   - paused: Whether game is paused
    ///   - gameOver: Whether game is over
    ///   - terminalSize: Optional terminal size override
    /// - Returns: String ready for output to terminal
    func render(
        grid: [[BlockState]],
        currentPiece: Tetromino?,
        currentX: Int,
        currentY: Int,
        nextPiece: Tetromino?,
        score: Int,
        level: Int,
        dropInterval: TimeInterval,
        paused: Bool,
        gameOver: Bool,
        terminalSize: (rows: Int, cols: Int)? = nil
    ) -> String {
        let size = terminalSize ?? terminal.getTerminalSize()
        let width = grid.first?.count ?? 10
        let height = grid.count
        let boardWidth = width * 2 + 2
        let boardHeight = height + 2
        let padLeft = max(0, (size.cols - boardWidth) / 2)
        let padTop = max(0, (size.rows - boardHeight - 4) / 2)
        let startRow = padTop + 1
        let startCol = padLeft + 1
        let nextCol = max(1, startCol - 12)

        var output = terminal.home + terminal.eraseDown

        // Draw next piece preview
        if let next = nextPiece {
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
                let currentCell = grid[y][x]
                var color: TetrominoColor?

                // Check if grid cell is filled
                if currentCell.isFilled {
                    color = currentCell.color
                } else if let piece = currentPiece {
                    // Check if current piece covers this cell
                    for (px, py) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
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

        let scoreText = "Score: \(score)  Level: \(level)"
        let controlsText = "Controls: j=left  k=rotate  l=right  SPACE=drop  q=quit"
        let statusText = paused ? "PAUSED - Press ESC to resume" : "Drop: \(String(format: "%.2fs", dropInterval))"

        output += terminal.cursorPosition(row: startRow + height + 3, col: centerColumn(for: scoreText))
        output += "Score: " + terminal.bold + String(score) + terminal.reset + "  Level: " + terminal.bold + String(level) + terminal.reset

        output += terminal.cursorPosition(row: startRow + height + 4, col: centerColumn(for: controlsText))
        output += controlsText

        output += terminal.cursorPosition(row: startRow + height + 5, col: centerColumn(for: statusText))
        if paused {
            output += terminal.bold + TetrominoColor.red.ansiCode + statusText + terminal.reset
        } else {
            output += statusText
        }

        return output
    }
}
