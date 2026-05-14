// TetrisGame.swift - Core game logic (UI-agnostic)

import Foundation

public class TetrisGame {
    let width: Int = 10
    let height: Int = 20
    public var grid: [[BlockState]]
    public var currentPiece: Tetromino?
    public var nextPiece: Tetromino?
    public var gameOver = false
    public var score = 0
    public var linesCleared = 0
    public var paused = false

    public var level: Int {
        min(10, max(1, linesCleared / 10 + 1))
    }

    private var currentX = 0
    private var currentY = 0
    private var lockDelay: TimeInterval = 0.5
    private var lockTime: Date?

    // Public for renderer
    public var pieceX: Int { currentX }
    public var pieceY: Int { currentY }

    // Game state snapshot for UI rendering
    public var gameState: GameSessionState {
        GameSessionState(
            grid: grid,
            currentPiece: currentPiece,
            currentX: currentX,
            currentY: currentY,
            nextPiece: nextPiece,
            score: score,
            level: level,
            paused: paused,
            gameOver: gameOver
        )
    }

    // Check if lock timer has expired
    public func shouldLock(_ now: Date = Date()) -> Bool {
        guard let lockTime = lockTime else { return false }
        return now >= lockTime
    }

    public init() {
        grid = Array(repeating: Array(repeating: .empty, count: width), count: height)
        spawnNextPiece()
        spawnNewPiece()
    }

    public func spawnNextPiece() {
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        guard let shape = shapes.randomElement() else { return }
        nextPiece = Tetromino(shape: shape)
    }

    public func spawnNewPiece() {
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

    public func isColliding() -> Bool {
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

    public func moveLeft() {
        currentX -= 1
        if isColliding() {
            currentX += 1
            return
        }
    }

    public func moveRight() {
        currentX += 1
        if isColliding() {
            currentX -= 1
            return
        }
    }

    public func moveDown() {
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

    public func canMoveDown() -> Bool {
        currentY += 1
        let colliding = isColliding()
        currentY -= 1
        return !colliding
    }

    public func rotatePiece() {
        guard let piece = currentPiece else { return }
        piece.rotate()
        if isColliding() {
            piece.rotateBack()
            return
        }
    }

    public func hardDrop() {
        while true {
            currentY += 1
            if isColliding() {
                currentY -= 1
                break
            }
        }
        // After hard drop, immediately set lock time
        lockTime = Date().addingTimeInterval(lockDelay)
    }

    public func lockPiece() {
        guard let piece = currentPiece else { return }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = .filled(piece.shape.blockColor)
            }
        }
        currentPiece = nil
    }

    public func clearLines() {
        var linesToClear: [Int] = []
        for y in 0..<height {
            if grid[y].allSatisfy({ $0.isFilled }) {
                linesToClear.append(y)
            }
        }

        guard !linesToClear.isEmpty else { return }

        for y in linesToClear.sorted(by: >) {
            grid.remove(at: y)
            grid.insert(Array(repeating: .empty, count: width), at: 0)
            score += 100
            linesCleared += 1
        }
    }

    public func spawnNewPieceAndClear() {
        lockPiece()
        clearLines()
        spawnNewPiece()
    }
}

/// Immutable snapshot of game state for UI rendering
public struct GameSessionState {
    public let grid: [[BlockState]]
    public let currentPiece: Tetromino?
    public let currentX: Int
    public let currentY: Int
    public let nextPiece: Tetromino?
    public let score: Int
    public let level: Int
    public let paused: Bool
    public let gameOver: Bool
}
