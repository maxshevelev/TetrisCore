// ConsoleRenderer.swift - Renders game state to ANSI escape sequences

import Foundation
import Model

public protocol GameRenderer {
    func render(data: GameSessionState) -> String
}

public struct ConsoleRenderer: GameRenderer, @unchecked Sendable {
    private let terminal: TerminalOperations

    public init(terminal: TerminalOperations) {
        self.terminal = terminal
    }

    public func render(data: GameSessionState) -> String {
        let size = terminal.getTerminalSize()
        let width = data.grid.first?.count ?? 10
        let height = data.grid.count
        let boardWidth = width * 2 + 2
        let boardHeight = height + 2
        let padLeft = max(0, (size.cols - boardWidth) / 2)
        let padTop = max(0, (size.rows - boardHeight - 4) / 2)
        let startRow = padTop + 1
        let startCol = padLeft + 1
        let nextCol = max(1, startCol - 12)
        let dropInterval = max(0.15, 0.8 - Double(data.level - 1) * 0.06)

        var output = terminal.home + terminal.eraseDown

        // Draw next piece preview
        if !data.nextPieceBlocks.isEmpty {
            output += terminal.cursorPosition(row: startRow, col: nextCol)
            output += terminal.bold + "Next:" + terminal.reset
            for y in 0..<4 {
                output += terminal.cursorPosition(row: startRow + y + 1, col: nextCol)
                for x in 0..<4 {
                    if let block = data.nextPieceBlocks.first(where: { $0.x == x && $0.y == y }) {
                        output += block.color.ansiCode + "██" + terminal.reset
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
                let currentCell = data.grid[y][x]
                var color: TetrominoColor?

                if currentCell.isFilled {
                    color = currentCell.color
                } else if let block = data.pieceBlocks.first(where: { $0.x == x && $0.y == y }) {
                    color = block.color
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

        let scoreText = "Score: \(data.score)  Level: \(data.level)"
        let controlsText = "Controls: j=left  k=rotate  l=right  SPACE=drop  q=quit"
        let statusText: String
        switch data.state {
        case .initializing:
            statusText = "Initializing..."
        case .dropping:
            statusText = "Drop: \(String(format: "%.2fs", dropInterval))"
        case .locking:
            statusText = "Locking piece..."
        case .paused:
            statusText = "PAUSED - Press ESC to resume"
        case .gameOver:
            statusText = "Game Over! ESC - exit, SPACE - new game"
        }

        if data.state == .gameOver {
            let overlay = renderGameOverOverlay(score: data.score, level: data.level, startRow: startRow, startCol: startCol, width: width, height: height)
            output += overlay
        } else {
            output += terminal.cursorPosition(row: startRow + height + 3, col: centerColumn(for: scoreText))
            output += "Score: " + terminal.bold + String(data.score) + terminal.reset + "  Level: " + terminal.bold + String(data.level) + terminal.reset

            output += terminal.cursorPosition(row: startRow + height + 4, col: centerColumn(for: controlsText))
            output += controlsText

            output += terminal.cursorPosition(row: startRow + height + 5, col: centerColumn(for: statusText))
            if data.state == .paused {
                output += terminal.bold + TetrominoColor.red.ansiCode + statusText + terminal.reset
            } else {
                output += statusText
            }
        }

        return output
    }

    private func renderGameOverOverlay(
        score: Int,
        level: Int,
        startRow: Int,
        startCol: Int,
        width: Int,
        height: Int
    ) -> String {
        let boardWidth = width * 2 + 2
        let overlayWidth = 28
        let overlayHeight = 9
        let overlayStartRow = startRow + max(0, (height - overlayHeight) / 2)
        let overlayStartCol = startCol + max(0, (boardWidth - overlayWidth) / 2)

        let topBorder = String(repeating: "═", count: overlayWidth)
        let scoreText = String(format: "Score: %d", score)
        let levelText = String(format: "Level: %d", level)

        let lines: [(text: String, isHighlighted: Bool)] = [
            ("GAME OVER", true),
            (scoreText, false),
            (levelText, false),
            ("", false),
            ("Press SPACE for new game", false),
            ("Press ESC to exit", false),
        ]

        var output = ""
        // Top border
        output += terminal.cursorPosition(row: overlayStartRow, col: overlayStartCol)
        output += terminal.bold + "╔" + topBorder + "╗" + terminal.reset

        // Content lines
        for (index, line) in lines.enumerated() {
            let row = overlayStartRow + index + 1
            output += terminal.cursorPosition(row: row, col: overlayStartCol)
            output += terminal.bold + "║" + terminal.reset
            if line.isHighlighted {
                output += TetrominoColor.red.ansiCode + terminal.bold + line.text + String(repeating: " ", count: max(0, overlayWidth - line.text.count)) + terminal.reset
            } else {
                output += line.text + String(repeating: " ", count: max(0, overlayWidth - line.text.count))
            }
            output += terminal.bold + "║" + terminal.reset
        }

        // Bottom border
        output += terminal.cursorPosition(row: overlayStartRow + lines.count + 1, col: overlayStartCol)
        output += terminal.bold + "╚" + topBorder + "╝" + terminal.reset

        return output
    }
}
