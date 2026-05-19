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
            let overlay = renderGameOverOverlay(score: data.score, level: data.level, topScores: data.topScores, terminalSize: size)
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

    // MARK: - Overlay

    enum Alignment { case leading, center, trailing }
    enum LineColor { case `none`, color(TetrominoColor) }

    struct OverlayLine {
        let text: String
        let alignment: Alignment
        let color: LineColor

        static func plain(_ text: String) -> OverlayLine {
            OverlayLine(text: text, alignment: .center, color: .none)
        }

        static func colored(_ text: String, _ color: TetrominoColor) -> OverlayLine {
            OverlayLine(text: text, alignment: .center, color: .color(color))
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
            switch line.color {
            case .none:
                output += line.text
            case .color(let c):
                output += c.ansiCode + terminal.bold + line.text + terminal.reset
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
        topScores: [Model.StoredScore],
        terminalSize: (rows: Int, cols: Int)
    ) -> String {
        var lines: [OverlayLine] = [
            OverlayLine.colored("GAME OVER", .red),
            OverlayLine.plain(String(format: "Score: %d", score)),
            OverlayLine.plain(String(format: "Level: %d", level)),
        ]

        if !topScores.isEmpty {
            lines.append(OverlayLine.plain(""))
            lines.append(OverlayLine.colored("Top Scores", .yellow))
            for (i, entry) in topScores.enumerated() {
                lines.append(OverlayLine.plain(
                    String(format: "%d. %d  (lvl %d)", i + 1, entry.score, entry.level)))
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
