// TetrisGame.swift - Core game logic (UI-agnostic)

import Foundation

class TetrisGame {
    let width: Int = 10
    let height: Int = 20
    var grid: [[BlockState]]
    var currentPiece: Tetromino?
    var nextPiece: Tetromino?
    var gameOver = false
    var score = 0
    var linesCleared = 0
    var paused = false

    var level: Int {
        min(10, max(1, linesCleared / 10 + 1))
    }

    private var currentX = 0
    private var currentY = 0
    private var lockDelay: TimeInterval = 0.5
    private var lockTime: Date?

    // Public for renderer
    var pieceX: Int { currentX }
    var pieceY: Int { currentY }

    // Check if lock timer has expired
    func shouldLock(_ now: Date = Date()) -> Bool {
        guard let lockTime = lockTime else { return false }
        return now >= lockTime
    }

    init() {
        grid = Array(repeating: Array(repeating: .empty, count: width), count: height)
        spawnNextPiece()
        spawnNewPiece()
    }

    private func spawnNextPiece() {
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        guard let shape = shapes.randomElement() else { return }
        nextPiece = Tetromino(shape: shape)
    }

    private func spawnNewPiece() {
        currentPiece = nextPiece
        if currentPiece != nil {
            currentX = width / 2 - 2
            currentY = -1

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
            if y >= 0 && grid[y][x].isFilled {
                return true
            }
        }
        return false
    }

    func moveLeft() {
        currentX -= 1
        if isColliding() {
            currentX += 1
            return
        }
    }

    func moveRight() {
        currentX += 1
        if isColliding() {
            currentX -= 1
            return
        }
    }

    func moveDown() {
        currentY += 1
        if isColliding() {
            currentY -= 1
            // Lock timer: set if not already set (allows user movement to reset it)
            if lockTime == nil {
                lockTime = Date().addingTimeInterval(lockDelay)
            }
        } else {
            // Can still move, clear lock timer
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
    }

    func hardDrop() {
        while true {
            currentY += 1
            if isColliding() {
                currentY -= 1
                break
            }
        }
    }

    func lockPiece() {
        guard let piece = currentPiece else { return }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = .filled(piece.shape.blockColor)
            }
        }
        currentPiece = nil
    }

    func clearLines() {
        var linesToClear: [Int] = []
        for y in 0..<height {
            if grid[y].allSatisfy({ $0.isFilled }) {
                linesToClear.append(y)
            }
        }

        for y in linesToClear.sorted(by: >) {
            grid.remove(at: y)
            grid.insert(Array(repeating: .empty, count: width), at: 0)
            score += 100
            linesCleared += 1
        }
    }

    func spawnNewPieceAndClear() {
        lockPiece()
        clearLines()
        spawnNewPiece()
    }
}
