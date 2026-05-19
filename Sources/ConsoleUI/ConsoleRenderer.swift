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

        // Player name above grid
        let playerLine = data.state == .gameOver ? nil : ("Player: " + data.playerName)
        if let playerLine {
            output += terminal.cursorPosition(row: startRow - 2, col: centerColumn(for: playerLine))
            output += terminal.bold + playerLine + terminal.reset
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
            let offset = (boardWidth - text.count) / 2
            return max(1, startCol + offset)
        }

        let scoreText = "Score: \(data.score)  Level: \(data.level)"
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
            statusText = "Game Over"
        }

        // Compute layout positions
        let controlsCol = min(startCol + boardWidth + 6, size.cols - 12)

        let controlsItems = [
            "j - left",
            "k - rotate",
            "l - right",
            "SPACE - drop",
            "ESC - pause",
            "q - quit",
        ]

        if data.state == .gameOver {
            let overlay = renderGameOverOverlay(score: data.score, level: data.level, playerName: data.playerName, topScores: data.topScores, terminalSize: size)
            output += overlay
        } else {
            // Score line
            output += terminal.cursorPosition(row: startRow + height + 4, col: centerColumn(for: scoreText))
            output += "Score: " + terminal.bold + String(data.score) + terminal.reset + "  Level: " + terminal.bold + String(data.level) + terminal.reset

            // Empty line
            // Status line
            output += terminal.cursorPosition(row: startRow + height + 6, col: centerColumn(for: statusText))
            if data.state == .paused {
                output += terminal.bold + TetrominoColor.red.ansiCode + statusText + terminal.reset
            } else {
                output += statusText
            }

            // Next piece preview (left side)
            if !data.nextPieceBlocks.isEmpty {
                output += terminal.cursorPosition(row: startRow, col: nextCol)
                output += terminal.bold + "Next:" + terminal.reset
                for y in 0..<4 {
                    output += terminal.cursorPosition(row: startRow + y + 2, col: nextCol)
                    for x in 0..<4 {
                        if let block = data.nextPieceBlocks.first(where: { $0.x == x && $0.y == y }) {
                            output += block.color.ansiCode + "██" + terminal.reset
                        } else {
                            output += "  "
                        }
                    }
                }
            }

            // Controls (right side)
            output += terminal.cursorPosition(row: startRow, col: controlsCol)
            output += terminal.bold + "Controls:" + terminal.reset
            for (i, item) in controlsItems.enumerated() {
                output += terminal.cursorPosition(row: startRow + i + 2, col: controlsCol)
                output += item
            }
        }

        return output
    }

    // MARK: - Overlay

    enum Alignment { case leading, center, trailing }
    enum LineColor { case `none`, color(TetrominoColor) }

    struct OverlayLine {
        let text: String
        let alignment: Alignment
        let color: TetrominoColor?
        let isBold: Bool

        static func plain(_ text: String, bold: Bool = false, color: TetrominoColor? = nil) -> OverlayLine {
            OverlayLine(text: text, alignment: .center, color: color, isBold: bold)
        }

        static func bold(_ text: String, color: TetrominoColor? = nil) -> OverlayLine {
            OverlayLine(text: text, alignment: .center, color: color, isBold: true)
        }
    }

    private func renderOverlay(
        lines: [OverlayLine],
        centeredIn area: (row: Int, col: Int, height: Int, width: Int)
    ) -> String {
        let innerWidth = max(lines.map { $0.text.count }.max()!, 1) + 2
        let totalWidth = innerWidth + 2
        let totalHeight = lines.count + 2
        let startRow = area.row + max(0, (area.height - totalHeight) / 2)
        let startCol = area.col + max(0, (area.width - totalWidth) / 2)
        let border = String(repeating: "═", count: innerWidth)

        var output = ""
        output += terminal.cursorPosition(row: startRow, col: startCol)
        output += terminal.bold + "╔" + border + "╗" + terminal.reset

        for (i, line) in lines.enumerated() {
            let r = startRow + i + 1
            output += terminal.cursorPosition(row: r, col: startCol)
            output += terminal.bold + "║" + terminal.reset

            let contentLen = line.text.count
            let available = max(innerWidth - contentLen, 0)
            let (leftPad, rightPad): (Int, Int)
            switch line.alignment {
            case .leading:  leftPad = 0; rightPad = available
            case .center:   leftPad = available / 2; rightPad = available - leftPad
            case .trailing: leftPad = available; rightPad = 0
            }
            output += String(repeating: " ", count: leftPad)
            if let textColor = line.color {
                output += textColor.ansiCode + terminal.bold + line.text + terminal.reset
            } else if line.isBold {
                output += terminal.bold + line.text + terminal.reset
            } else {
                output += line.text
            }
            output += String(repeating: " ", count: rightPad)
            output += terminal.bold + "║" + terminal.reset
        }

        output += terminal.cursorPosition(row: startRow + lines.count + 1, col: startCol)
        output += terminal.bold + "╚" + border + "╝" + terminal.reset
        return output
    }

    private func renderGameOverOverlay(
        score: Int,
        level: Int,
        playerName: String,
        topScores: [Model.StoredScore],
        terminalSize: (rows: Int, cols: Int)
    ) -> String {
        var lines: [OverlayLine] = [
            OverlayLine.bold("GAME OVER", color: .red),
            OverlayLine.plain("User: " + playerName + "  Score: " + String(format: "%d", score)),
            OverlayLine.plain(String(format: "Level: %d", level)),
        ]

        if !topScores.isEmpty {
            lines.append(OverlayLine.plain(""))
            lines.append(OverlayLine.bold("Top Scores"))
            for (i, entry) in topScores.enumerated() {
                let rankText = String(format: "%d. %@ %d  (lvl %d)", i + 1, entry.playerName, entry.score, entry.level)
                let isCurrent = entry.score == score && entry.playerName == playerName
                if isCurrent {
                    lines.append(OverlayLine.plain("  " + rankText + " ←"))
                } else {
                    lines.append(OverlayLine.plain(rankText))
                }
            }
        }

        lines.append(OverlayLine.plain(""))
        lines.append(OverlayLine.plain("Press SPACE for new game"))
        lines.append(OverlayLine.plain("Press ESC to exit"))

        return renderOverlay(
            lines: lines,
            centeredIn: (row: 1, col: 1, height: terminalSize.rows, width: terminalSize.cols)
        )
    }
}
