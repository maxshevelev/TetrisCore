// TetrisGame.swift - Core game logic (UI-agnostic)

import Foundation

/// Protocol for listening to game events
protocol GameEventListener: AnyObject {
    func onGameEvent(_ event: GameEvent)
}

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

    // Event listener (weak to avoid retain cycles)
    weak var listener: GameEventListener?

    // Game state snapshot for UI polling
    var gameState: GameSessionState {
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
    func shouldLock(_ now: Date = Date()) -> Bool {
        guard let lockTime = lockTime else { return false }
        return now >= lockTime
    }

    /// Update game state with elapsed time
    /// Call this each frame with the time delta to handle auto-drop and lock timing
    func update(_ deltaTime: TimeInterval, now: Date = Date()) {
        guard !paused && !gameOver else { return }

        // Check for piece lock delay
        if shouldLock(now) {
            if currentPiece != nil {
                if canMoveDown() {
                    moveDown()
                } else {
                    lockPiece()
                    clearLines()
                    spawnNewPieceAndClear()
                }
            }
        }
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
                notify(.gameOver)
            }
        }
        spawnNextPiece()
        notify(.pieceSpawned)
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
        notify(.pieceMoved)
    }

    func moveRight() {
        currentX += 1
        if isColliding() {
            currentX -= 1
            return
        }
        notify(.pieceMoved)
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
        notify(.pieceMoved)
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
        notify(.pieceRotated)
    }

    func hardDrop() {
        while true {
            currentY += 1
            if isColliding() {
                currentY -= 1
                break
            }
        }
        // After hard drop, immediately set lock time
        lockTime = Date().addingTimeInterval(lockDelay)
        notify(.pieceMoved)
    }

    func lockPiece() {
        guard let piece = currentPiece else { return }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = .filled(piece.shape.blockColor)
            }
        }
        currentPiece = nil
        notify(.pieceLocked)
    }

    func clearLines() {
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

        notify(.scoreChanged(score: score))
        notify(.levelChanged(level: level))
        notify(.lineCleared(lines: linesToClear.count, score: score))
    }

    func spawnNewPieceAndClear() {
        lockPiece()
        clearLines()
        spawnNewPiece()
    }

    // Notify listener of events
    private func notify(_ event: GameEvent) {
        listener?.onGameEvent(event)
    }
}

/// Immutable snapshot of game state for UI rendering
struct GameSessionState {
    let grid: [[BlockState]]
    let currentPiece: Tetromino?
    let currentX: Int
    let currentY: Int
    let nextPiece: Tetromino?
    let score: Int
    let level: Int
    let paused: Bool
    let gameOver: Bool
}
