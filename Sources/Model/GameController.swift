// GameController.swift - Owns game timing and event-driven loop
// Actor provides data-race-free concurrent access

import Foundation
import os

public actor GameController: InputReceiver {
    // MARK: - Constants

    private static let baseScores: [Int: Int] = [1: 40, 2: 100, 3: 300, 4: 1200]

    private let width = 10
    private let height = 20
    private let lockDelay: TimeInterval = 0.5

    /// All valid state transitions. Any transition not in this table is silently rejected.
    private static let validTransitions: [GameState: Set<GameState>] = [
        .initializing: [.dropping],
        .dropping: [.locking, .paused, .gameOver],
        .locking: [.dropping, .gameOver],
        .paused: [.dropping, .gameOver],
        .gameOver: [.initializing],
    ]

    // MARK: - State

    private var state: GameState = .initializing {
        didSet {
            log(.debug,"[State] \(oldValue) -> \(state)")
            switch state {
            case .dropping:
                stopLockTimer()
                resetDropTimer()
            case .locking:
                stopDropTimer()
                resetLockTimer()
            case .paused:
                stopDropTimer()
                stopLockTimer()
            case .gameOver:
                stopDropTimer()
                stopLockTimer()
                if oldValue != .gameOver {
                    log(.debug,"[Score] Saving score=\(score) level=\(level) player=\(playerName)")
                    scoreStorage.add(score: score, level: level, playerName: playerName)
                }
            default: break
            }
        }
    }

    /// Transition to `newState` only if the transition is valid.
    /// Invalid transitions are silently rejected with a debug log.
    private func transition(to newState: GameState) {
        guard let allowed = Self.validTransitions[state], allowed.contains(newState) else {
            log(.debug,"[State] Invalid transition: \(state) -> \(newState), blocked")
            return
        }
        state = newState
    }

    private var grid: [[BlockState]]
    private var currentPiece: Tetromino?
    private var nextPiece: Tetromino?
    private var currentX = 0
    private var currentY = 0
    private var score = 0
    private var linesCleared = 0

    // MARK: - Dependencies

    private let inputBuffer = InputBuffer()

    // MARK: - Logger

    private let log: Logger
    private let minLogLevel: LogLevel?

    // MARK: - Score Storage

    private let scoreStorage: ScoreStorage
    private let playerName: String

    // MARK: - Callbacks

    private let onRender: @Sendable (GameSessionState) -> Void
    private let onGameFinished: @Sendable () -> Void

    public init(
        logger: Logger = Logger(),
        logLevel: LogLevel? = nil,
        scoreStorage: ScoreStorage = ScoreStorage(),
        playerName: String = defaultPlayerName(),
        onRender: @escaping @Sendable (GameSessionState) -> Void,
        onGameFinished: @escaping @Sendable () -> Void
    ) {
        self.minLogLevel = logLevel
        self.log = logger
        self.scoreStorage = scoreStorage
        self.playerName = playerName
        self.onRender = onRender
        self.onGameFinished = onGameFinished
        self.grid = Array(repeating: Array(repeating: .empty, count: width), count: height)
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        self.nextPiece = Tetromino(shape: shapes.randomElement()!)
        self.currentPiece = self.nextPiece
        self.currentX = width / 2 - 2
        self.currentY = 0
        self.nextPiece = Tetromino(shape: shapes.randomElement()!)
    }

    // MARK: - Computed

    private var level: Int {
        min(10, max(1, linesCleared / 10 + 1))
    }

    private var dropInterval: TimeInterval {
        max(0.15, 0.8 - Double(level - 1) * 0.06)
    }

    // MARK: - Lifecycle

    private var dropTimer: Task<Void, Never>?
    private var lockTimer: Task<Void, Never>?

    private func resetDropTimer() {
        dropTimer?.cancel()
        dropTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(dropInterval * 1_000_000_000))
            guard state == .dropping else { return }
            if canMoveDownPrivate() {
                currentY += 1
                resetDropTimer()
            } else {
                transition(to: .locking)
            }
            render()
        }

    }

    private func stopDropTimer() {
        dropTimer?.cancel()
        dropTimer = nil
    }

    private func resetLockTimer() {
        lockTimer?.cancel()
        lockTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(lockDelay * 1_000_000_000))
            guard state == .locking else { return }
            if !canMoveDownPrivate() {
                lockPiecePrivate()
                clearLinesPrivate()
                spawnNewPiece()
            }
            transition(to: .dropping)
            render()
        }
    }

    private func stopLockTimer() {
        lockTimer?.cancel()
        lockTimer = nil
    }

    private func log(_ level: LogLevel, _ message: String) {
        guard let minLogLevel, minLogLevel.allows(level) else { return }
        switch level {
        case .debug:    log.debug("\(message, privacy: .public)")
        case .info, .notice: log.info("\(message, privacy: .public)")
        case .error:    log.error("\(message, privacy: .public)")
        case .fault:    log.fault("\(message, privacy: .public)")
        }
    }

    public func start() {
        log(.debug,"[LifeCycle] Game started")
        render()
        startInputListener()
        transition(to: .dropping)
    }

    private func resetGame() {
        grid = Array(repeating: Array(repeating: .empty, count: width), count: height)
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        nextPiece = Tetromino(shape: shapes.randomElement()!)
        currentPiece = nextPiece
        currentX = width / 2 - 2
        currentY = 0
        nextPiece = Tetromino(shape: shapes.randomElement()!)
        score = 0
        linesCleared = 0
    }

    private func restart() {
        log(.debug,"[LifeCycle] Game restarted")
        resetGame()
        transition(to: .initializing)
        transition(to: .dropping)
        render()
    }

    // MARK: - Input Receiver

    public func enqueue(_ event: KeyEvent) async {
        await inputBuffer.send(event)
    }

    var isPlaying: Bool {
        (state == .dropping || state == .locking)
    }

    private func startInputListener() {
        Task {
            while true {
                let keyEvent = await self.inputBuffer.receive()

                switch keyEvent {
                case .moveLeft:
                    log(.debug,"[Input] move_left at x=\(currentX)")
                    guard isPlaying else { continue }
                    moveLeft()
                case .moveRight:
                    log(.debug,"[Input] move_right at x=\(currentX)")
                    guard isPlaying else { continue }
                    moveRight()
                case .rotate:
                    log(.debug,"[Input] rotate")
                    guard isPlaying else { continue }
                    rotatePiece()
                case .hardDrop:
                    log(.debug,"[Input] hard_drop at y=\(currentY)")
                    if isPlaying {
                        hardDropPiece()
                    } else if state == .gameOver {
                        restart()
                    } else {
                        continue
                    }
                case .esc:
                    log(.debug,"[Input] esc")
                    if isPlaying {
                        transition(to: .paused)
                    } else if state == .paused {
                        transition(to: .dropping)
                    } else if state == .gameOver {
                        finish()
                        return // and finish the input listener task
                    } else {
                        continue
                    }
                case .quit:
                    log(.debug,"[Input] quit")
                    transition(to: .gameOver)
                }
                render()
            }
        }
    }

    // MARK: - Testable Game Logic Methods

    public func moveLeft() {
        guard isPlaying else { return }
        currentX -= 1
        if isColliding() {
            currentX += 1
        }
    }

    public func moveRight() {
        guard isPlaying else { return }
        currentX += 1
        if isColliding() {
            currentX -= 1
        }
    }

    public func rotatePiece() {
        guard isPlaying else { return }
        guard let piece = currentPiece else { return }
        let rotated = piece.rotated(by: -1)
        let oldPiece = currentPiece
        currentPiece = rotated
        if isColliding() {
            currentPiece = oldPiece
        }
    }

    public func hardDropPiece() {
        guard isPlaying else { return }
        while canMoveDownPrivate() { currentY += 1 }
        transition(to: .locking)
    }

    private func canMoveDownPrivate() -> Bool {
        currentY += 1
        let colliding = isCollidingPrivate()
        currentY -= 1
        return !colliding
    }

    public func isColliding() -> Bool {
        isCollidingPrivate()
    }

    private func isCollidingPrivate() -> Bool {
        guard let piece = currentPiece else { return false }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if x < 0 || x >= width || y >= height { return true }
            if y >= 0 && grid[y][x].isFilled { return true }
        }
        return false
    }

    private func lockPiecePrivate() {
        guard let piece = currentPiece else { return }
        log(.debug,"[Piece] Locked \([piece.shape.rawValue]) at (\(currentX),\(currentY))")
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = .filled(piece.shape.blockColor)
            }
        }
        currentPiece = nil
    }

    private func clearLinesPrivate() {
        let linesToClear = grid.indices.filter { grid[$0].allSatisfy { $0.isFilled } }
        let count = linesToClear.count
        if count == 0 { return }
        score += Self.baseScores[count, default: 0] * (level + 1)
        linesCleared += count
        log(.debug,"[Lines] Cleared \(count) line(s), score=\(score) total_lines=\(linesCleared)")
        // Remove from bottom to top so indices stay valid
        for y in linesToClear.reversed() {
            grid.remove(at: y)
        }
        grid.insert(contentsOf: Array(repeating: Array(repeating: .empty, count: width), count: count), at: 0)
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
            currentY = 0
            log(.debug,"[Piece] Spawned \([currentPiece!.shape.rawValue])")
            if isColliding() {
                log(.debug,"[GameOver] Score: \(score) Lines: \(linesCleared)")
                transition(to: .gameOver)
            }
        }
        spawnNextPiece()
    }

    // MARK: - Render

    private func render() {
        let pieceBlocks: [PieceBlock]
        if let piece = currentPiece {
            pieceBlocks = piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY)
                .map { PieceBlock(x: $0.x, y: $0.y, color: piece.shape.blockColor) }
        } else {
            pieceBlocks = []
        }

        let nextPieceBlocks: [PieceBlock]
        if let next = nextPiece {
            nextPieceBlocks = next.getAbsoluteCoordinates(xOffset: 0, yOffset: 0)
                .map { PieceBlock(x: $0.x, y: $0.y, color: next.shape.blockColor) }
        } else {
            nextPieceBlocks = []
        }

        onRender(
            GameSessionState(
                grid: grid,
                pieceBlocks: pieceBlocks,
                nextPieceBlocks: nextPieceBlocks,
                score: score,
                level: level,
                linesCleared: linesCleared,
                state: state,
                topScores: scoreStorage.topScores(),
                playerName: playerName
            ))
    }

    private func finish() {
        render()
        onGameFinished()
    }
}
