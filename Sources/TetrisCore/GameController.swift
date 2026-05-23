// GameController.swift - Owns game timing and event-driven loop
// Actor provides data-race-free concurrent access

import Foundation
import os

public actor GameController: InputReceiver {
    // MARK: - Constants

    private static let baseScores: [Int: Int] = [1: 40, 2: 100, 3: 300, 4: 1200]

    private let width = 10
    private let height = 20

    /// All valid state transitions. Any transition not in this table is silently rejected.
    private static let validTransitions: [GameState: Set<GameState>] = [
        .initializing: [.dropping],
        .dropping: [.paused, .gameOver, .dropping],
        .paused: [.dropping, .gameOver],
        .gameOver: [.initializing],
    ]

    // MARK: - State

    private var state: GameState = .initializing {
        didSet {
            log(.debug,"[State] \(oldValue) -> \(state)")
            switch state {
            case .dropping:
                resetDropTimer()
            case .paused:
                stopDropTimer()
            case .gameOver:
                stopDropTimer()
                if oldValue != .gameOver {
                    log(.debug,"[Score] Saving score=\(score) level=\(level) player=\(settings.playerName)")
                    scoreStorage.add(score: score, playerName: settings.playerName)
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
    public let settings: any GameSettings

    // MARK: - Streams

    nonisolated public let tick: AsyncStream<Set<GameEvent>>
    nonisolated private let tickContinuation: AsyncStream<Set<GameEvent>>.Continuation

    /// Cached values for computing diffs on the tick channel.
    /// nil = never sent (first send includes all fields).
    private var sentGrid: [[BlockState]]?
    private var sentPieceCoords: Set<PieceCoordinate>?
    private var sentNextPieceCoords: Set<PieceCoordinate>?
    private var sentScore: Int?
    private var sentLevel: Int?
    private var sentLinesCleared: Int?
    private var sentDisplayState: GameDisplayState?
    private var sentTopScores: [StoredScore]?
    private var sentPlayerName: String?
    private var pendingHardDropDuration: TimeInterval?
    private var pendingClearedRows: (rows: Set<Int>, duration: TimeInterval)?

    public init(
        logger: Logger = Logger(),
        logLevel: LogLevel? = nil,
        scoreStorage: ScoreStorage = ScoreStorage(),
        settings: any GameSettings = PersistentGameSettings()
    ) {
        self.minLogLevel = logLevel
        self.log = logger
        self.scoreStorage = scoreStorage
        self.settings = settings
        self.grid = Array(repeating: Array(repeating: .empty, count: width), count: height)

        var tkc: AsyncStream<Set<GameEvent>>.Continuation!
        let tks = AsyncStream<Set<GameEvent>> { tkc = $0 }
        self.tickContinuation = tkc
        self.tick = tks

        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        self.nextPiece = Tetromino(shape: shapes.randomElement()!)
        self.currentPiece = self.nextPiece
        self.currentX = width / 2 - 2
        self.currentY = 0
        self.nextPiece = Tetromino(shape: shapes.randomElement()!)
    }

    // MARK: - Computed

    private var level: Int {
        min(10, linesCleared / 10 + settings.initialLevel)
    }

    private var dropInterval: TimeInterval {
        max(0.15, 0.8 - Double(level - 1) * 0.06)
    }

    /// Consumer-facing state — collapses internal timer states into `.playing`.
    private var displayState: GameDisplayState {
        switch state {
        case .dropping, .initializing: return .playing
        case .paused: return .paused
        case .gameOver: return .gameOver
        }
    }

    // MARK: - Lifecycle

    private var dropTimer: Task<Void, Never>?
    private var dropTimerGeneration = 0
    private var pieceBlockedOnLastTick = false

    private func resetDropTimer() {
        dropTimer?.cancel()
        let gen = dropTimerGeneration + 1
        dropTimerGeneration = gen
        dropTimer = Task {
            try? await Task.sleep(nanoseconds: UInt64(dropInterval * 1_000_000_000))
            guard dropTimerGeneration == gen else { return }
            guard state == .dropping else { return }
            if canMoveDown() {
                currentY += 1
                pieceBlockedOnLastTick = false
                transition(to: .dropping)
            } else if pieceBlockedOnLastTick {
                lockPiecePrivate()
                clearLinesPrivate()
                spawnNewPiece()
                pieceBlockedOnLastTick = false
                transition(to: .dropping)
            } else {
                pieceBlockedOnLastTick = true
                resetDropTimer()
            }
            render()
        }

    }

    private func stopDropTimer() {
        dropTimer?.cancel()
        dropTimer = nil
        dropTimerGeneration += 1
    }

    private func log(_ level: LogLevel, _ message: String) {
        guard let minLogLevel, minLogLevel.allows(level) else { return }
        switch level {
        case .debug:    self.log.debug("\(message, privacy: .public)")
        case .info, .notice: self.log.info("\(message, privacy: .public)")
        case .error:    self.log.error("\(message, privacy: .public)")
        case .fault:    self.log.fault("\(message, privacy: .public)")
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
        sentPlayerName = nil
        pendingClearedRows = nil
        pieceBlockedOnLastTick = false
    }

    private func restart() {
        log(.debug,"[LifeCycle] Game restarted")
        resetGame()
        transition(to: .initializing)
        transition(to: .dropping)
        render()
    }

    // MARK: - Input Receiver

    public func enqueue(_ event: ControlEvent) async {
        await inputBuffer.send(event)
    }

    private var isPlaying: Bool {
        state == .dropping
    }

    private func startInputListener() {
        Task {
            while true {
                let controlEvent = await self.inputBuffer.receive()

                switch controlEvent {
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
                case .pause:
                    log(.debug,"[Input] pause")
                    guard isPlaying else { continue }
                    transition(to: .paused)
                case .resume:
                    log(.debug,"[Input] resume")
                    guard state == .paused else { continue }
                    transition(to: .dropping)
                case .stop:
                    log(.debug,"[Input] stop")
                    transition(to: .gameOver)
                }
                render()
            }
        }
    }

    // MARK: - Input Actions

    private func moveLeft() {
        guard isPlaying else { return }
        currentX -= 1
        if isColliding() {
            currentX += 1
        }
    }

    private func moveRight() {
        guard isPlaying else { return }
        currentX += 1
        if isColliding() {
            currentX -= 1
        }
    }

    private func rotatePiece() {
        guard isPlaying else { return }
        guard let piece = currentPiece else { return }
        let rotated = piece.rotated(by: -1)
        let oldPiece = currentPiece
        currentPiece = rotated
        if isColliding() {
            currentPiece = oldPiece
        }
    }

    private func hardDropPiece() {
        guard isPlaying else { return }
        let startY = currentY
        while canMoveDown() { currentY += 1 }
        stopDropTimer()
        if settings.isHardDropAnimated, currentY != startY {
            let delay = min(dropInterval * 0.5, 0.25)
            pendingHardDropDuration = delay
            let gen = dropTimerGeneration + 1
            dropTimerGeneration = gen
            dropTimer = Task {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard dropTimerGeneration == gen else { return }
                guard state == .dropping else { return }
                if settings.lockImmediatelyAfterHardDrop {
                    lockPiecePrivate()
                    clearLinesPrivate()
                    spawnNewPiece()
                    pieceBlockedOnLastTick = false
                    transition(to: .dropping)
                } else {
                    pieceBlockedOnLastTick = true
                    transition(to: .dropping)
                }
                render()
            }
        } else if settings.lockImmediatelyAfterHardDrop {
            lockPiecePrivate()
            clearLinesPrivate()
            spawnNewPiece()
            transition(to: .dropping)
        } else {
            pieceBlockedOnLastTick = true
            transition(to: .dropping)
        }
    }

    private func canMoveDown() -> Bool {
        currentY += 1
        let colliding = isColliding()
        currentY -= 1
        return !colliding
    }

    private func isColliding() -> Bool {
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
        if settings.isLineClearAnimated {
            let duration = min(dropInterval * 0.5, 0.25)
            pendingClearedRows = (rows: Set(linesToClear), duration: duration)
        }
        removeClearedRows(linesToClear)
        log(.debug,"[Lines] Cleared \(count) line(s), score=\(score) total_lines=\(linesCleared) rows:\(linesToClear.sorted())")
    }

    private func removeClearedRows(_ linesToClear: [Int]) {
        let count = linesToClear.count
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
        let pieceCoords: Set<PieceCoordinate>
        let pieceColor: TetrominoColor
        if let piece = currentPiece {
            pieceCoords = Set(piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY)
                .map { PieceCoordinate(x: $0.x, y: $0.y) })
            pieceColor = piece.shape.blockColor
        } else {
            pieceCoords = []
            pieceColor = .red
        }

        let nextCoords: Set<PieceCoordinate>
        let nextColor: TetrominoColor
        if let next = nextPiece {
            nextCoords = Set(next.getAbsoluteCoordinates(xOffset: 0, yOffset: 0)
                .map { PieceCoordinate(x: $0.x, y: $0.y) })
            nextColor = next.shape.blockColor
        } else {
            nextCoords = []
            nextColor = .red
        }

        let gridCopy = grid
        let topScores = scoreStorage.topScores()

        var events = Set<GameEvent>()
        if gridCopy != sentGrid { events.insert(.grid(gridCopy)); sentGrid = gridCopy }
        if pieceCoords != sentPieceCoords || pendingHardDropDuration != nil {
            events.insert(.pieceBlocks(pieceCoords, color: pieceColor, hardDropDuration: pendingHardDropDuration))
            sentPieceCoords = pieceCoords
            pendingHardDropDuration = nil
        }
        if nextCoords != sentNextPieceCoords { events.insert(.nextPieceBlocks(nextCoords, color: nextColor)); sentNextPieceCoords = nextCoords }
        if score != sentScore { events.insert(.score(score)); sentScore = score }
        if level != sentLevel { events.insert(.level(level)); sentLevel = level }
        if linesCleared != sentLinesCleared || pendingClearedRows != nil {
            let rows = pendingClearedRows?.rows ?? []
            let duration = pendingClearedRows?.duration ?? 0
            events.insert(.linesCleared(linesCleared, clearedRows: rows, animationDuration: duration))
            sentLinesCleared = linesCleared
            pendingClearedRows = nil
        }
        if displayState != sentDisplayState { events.insert(.state(displayState)); sentDisplayState = displayState }
        if topScores != sentTopScores { events.insert(.topScores(topScores)); sentTopScores = topScores }
        if settings.playerName != sentPlayerName { events.insert(.playerName(settings.playerName)); sentPlayerName = settings.playerName }
        guard !events.isEmpty else { return }
        tickContinuation.yield(events)
    }

}
