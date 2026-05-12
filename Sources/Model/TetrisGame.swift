// Model/TetrisGame.swift

import Foundation

class TetrisGame {
    let width: Int = 10
    let height: Int = 20
    var grid: [[String]]
    var currentPiece: Tetromino?
    var nextPiece: Tetromino?
    var gameOver = false
    var score = 0
    var linesCleared = 0
    var paused = false
    var pieceColor = ""

    var level: Int {
        min(10, max(1, linesCleared / 10 + 1))
    }
    
    init() {
        grid = Array(repeating: Array(repeating: "", count: width), count: height)
        spawnNextPiece()
        spawnNewPiece()
    }

    private func spawnNextPiece() {
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        nextPiece = Tetromino(shape: shapes.randomElement()!)
    }

    private func spawnNewPiece() {
        currentPiece = nextPiece
        if let piece = currentPiece {
            pieceColor = piece.shape.color
            currentX = width / 2 - 2
            currentY = -1
            lastDropTime = Date()
            lockTime = nil

            if isColliding() {
                gameOver = true
            }
        }
        spawnNextPiece()
    }

    func isColliding() -> Bool {
        guard let piece = currentPiece else { return false }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if x < 0 || x >= width || y >= height {
                return true
            }
            if y >= 0 && grid[y][x] != "" {
                return true
            }
        }
        return false
    }

    private func resetLockDelay() {
        lockTime = Date().addingTimeInterval(lockDelay)
    }

    func moveLeft() {
        currentX -= 1
        if isColliding() {
            currentX += 1
            return
        }
        if lockTime != nil {
            resetLockDelay()
        }
    }

    func moveRight() {
        currentX += 1
        if isColliding() {
            currentX -= 1
            return
        }
        if lockTime != nil {
            resetLockDelay()
        }
    }

    func moveDown() {
        currentY += 1
        if isColliding() {
            currentY -= 1
            if lockTime == nil {
                resetLockDelay()
            }
        } else {
            lockTime = nil
        }
    }

    func canMoveDown() -> Bool {
        currentY += 1
        let colliding = isColliding()
        currentY -= 1
        return !colliding
    }

    func rotatePiece() {
        guard let piece = currentPiece else { return }
        piece.rotate()
        if isColliding() {
            piece.rotateBack()
            return
        }
        if lockTime != nil {
            resetLockDelay()
        }
    }

    func hardDrop() {
        while true {
            currentY += 1
            if isColliding() {
                currentY -= 1
                break
            }
        }
        if lockTime == nil {
            resetLockDelay()
        }
    }

    private func lockPiece() {
        guard let piece = currentPiece else { return }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = piece.shape.color
            }
        }
    }

    private func clearLines() {
        var linesToClear: [Int] = []
        for y in 0..<height {
            if grid[y].allSatisfy({ $0 != "" }) {
                linesToClear.append(y)
            }
        }

        for y in linesToClear.sorted(by: >) {
            grid.remove(at: y)
            grid.insert(Array(repeating: "", count: width), at: 0)
            score += 100
            linesCleared += 1
        }
    }

    func update() {
        if gameOver { return }

        let now = Date()
        if now.timeIntervalSince(lastDropTime) > dropInterval {
            moveDown()
            lastDropTime = now
        }

        if let lockTime = lockTime, now >= lockTime {
            if canMoveDown() {
                moveDown()
                lastDropTime = now
            } else {
                lockPiece()
                clearLines()
                spawnNewPiece()
                lastDropTime = now
            }
        }
    }

    func render() {
        let terminalSize = Terminal.getTerminalSize()
        let boardWidth = width * 2 + 2
        let boardHeight = height + 2
        let padLeft = max(0, (terminalSize.cols - boardWidth) / 2)
        let padTop = max(0, (terminalSize.rows - boardHeight - 4) / 2)
        let startRow = padTop + 1
        let startCol = padLeft + 1
        let nextCol = max(1, startCol - 12)

        var output = Terminal.home + Terminal.eraseDown

        // Draw next piece preview
        if let next = nextPiece {
            output += Terminal.cursorPosition(row: startRow, col: nextCol)
            output += Terminal.bold + "Next:" + Terminal.reset
            for y in 0..<4 {
                output += Terminal.cursorPosition(row: startRow + y + 1, col: nextCol)
                for x in 0..<4 {
                    var hasBlock = false
                    for (px, py) in next.getAbsoluteCoordinates(xOffset: 0, yOffset: 0) {
                        if px == x && py == y {
                            hasBlock = true
                            break
                        }
                    }
                    if hasBlock {
                        output += next.shape.color + "██" + Terminal.reset
                    } else {
                        output += "  "
                    }
                }
            }
        }

        output += Terminal.cursorPosition(row: startRow, col: startCol)
        output += Terminal.bold + "╔" + String(repeating: "═", count: width * 2) + "╗" + Terminal.reset

        for y in 0..<height {
            output += Terminal.cursorPosition(row: startRow + y + 1, col: startCol)
            output += Terminal.bold + "║" + Terminal.reset
            for x in 0..<width {
                let currentCell = grid[y][x]
                var color = currentCell
                if let piece = currentPiece {
                    for (px, py) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
                        if px == x && py == y {
                            color = pieceColor
                            break
                        }
                    }
                }
                if color != "" {
                    output += color + "██" + Terminal.reset
                } else {
                    output += "· "
                }
            }
            output += Terminal.bold + "║" + Terminal.reset
        }

        output += Terminal.cursorPosition(row: startRow + height + 1, col: startCol)
        output += Terminal.bold + "╚" + String(repeating: "═", count: width * 2) + "╝" + Terminal.reset

        func centerColumn(for text: String) -> Int {
            return startCol + max(0, (boardWidth - text.count) / 2)
        }

        let scoreText = "Score: \(score)  Level: \(level)"
        let controlsText = "Controls: j=left  k=rotate  l=right  SPACE=drop  q=quit"
        let statusText = paused ? "PAUSED - Press ESC to resume" : "Drop: \(String(format: "%.2fs", dropInterval))"

        output += Terminal.cursorPosition(row: startRow + height + 3, col: centerColumn(for: scoreText))
        output += "Score: " + Terminal.bold + String(score) + Terminal.reset + "  Level: " + Terminal.bold + String(level) + Terminal.reset

        output += Terminal.cursorPosition(row: startRow + height + 4, col: centerColumn(for: controlsText))
        output += controlsText

        output += Terminal.cursorPosition(row: startRow + height + 5, col: centerColumn(for: statusText))
        if paused {
            output += Terminal.bold + Terminal.red + statusText + Terminal.reset
        } else {
            output += statusText
        }

        print(output, terminator: "")
        fflush(stdout)
    }

    private let dropInterval: TimeInterval = 0.5
    private let lockDelay: TimeInterval = 0.5
    private var currentX = 0
    private var currentY = 0
    private var lastDropTime: Date!
    private var lockTime: Date?
}

