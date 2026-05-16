// GameController.swift - Owns game timing and event-driven loop
// Actor provides data-race-free concurrent access

import Foundation

public actor GameController: InputReceiver {
    // MARK: - Constants

    private let width = 10
    private let height = 20
    private let lockDelay: TimeInterval = 0.5

    // MARK: - State

    private var state: GameState = .initializing {
        didSet {
            switch state {
            case .dropping:
                stopLockTimer()
                makeDropTimer()
            case .locking:
                stopDropTimer()
                makeLockTimer()
            case .paused:
                stopDropTimer()
                stopLockTimer()
            case .gameOver:
                stopDropTimer()
                stopLockTimer()
                finish()
            default: break
            }
        }
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

    // MARK: - Callbacks

    private let onRender: @Sendable (GameSessionState) -> Void
    private let onGameOver: @Sendable () -> Void

    public nonisolated let doneSemaphore = DispatchSemaphore(value: 0)

    public init(
        onRender: @escaping @Sendable (GameSessionState) -> Void,
        onGameOver: @escaping @Sendable () -> Void
    ) {
        self.onRender = onRender
        self.onGameOver = onGameOver
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

    func createDropTimer(interval: TimeInterval) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard state == .dropping else { return }
            if canMoveDown() {
                currentY += 1
                state = .dropping
            } else {
                state = .locking
            }
            render()
        }
    }

    func makeDropTimer() {
        dropTimer?.cancel()
        dropTimer = createDropTimer(interval: dropInterval)
    }

    func stopDropTimer() {
        dropTimer?.cancel()
        dropTimer = nil
    }

    func createLockTimer(interval: TimeInterval) -> Task<Void, Never> {
        Task {
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard state == .locking else { return }
            if !canMoveDown() {
                lockPiece()
                clearLines()
                spawnNewPiece()
            }
            state = .dropping
            render()
        }
    }

    func stopLockTimer() {
        lockTimer?.cancel()
        lockTimer = nil
    }

    func makeLockTimer() {
        lockTimer?.cancel()
        lockTimer = createLockTimer(interval: lockDelay)
    }

    public func start() {
        render()
        startInputListener()
        state = .dropping
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
            while state != .gameOver {
                let keyEvent = await self.inputBuffer.receive()
                switch keyEvent {
                case .moveLeft:
                    guard isPlaying else { continue }
                    currentX -= 1
                    if isColliding() {
                        currentX += 1
                    }
                case .moveRight:
                    guard isPlaying else { continue }
                    currentX += 1
                    if isColliding() {
                        currentX -= 1
                    }
                case .rotate:
                    guard isPlaying else { continue }
                    guard let piece = currentPiece else { continue }
                    piece.rotate()
                    if isColliding() {
                        piece.rotateBack()
                        continue
                    }
                case .hardDrop:
                    guard isPlaying else { continue }
                    while canMoveDown() { currentY += 1 }
                    state = .locking
                case .togglePause:
                    if isPlaying {
                        state = .paused
                    } else if state == .paused {
                        state = .dropping
                    }
                case .quit:
                    state = .gameOver
                }
                render()
            }
        }
    }

    // MARK: - Game Logic

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

    private func lockPiece() {
        guard let piece = currentPiece else { return }
        for (x, y) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: currentY) {
            if y >= 0 && x >= 0 && x < width && y < height {
                grid[y][x] = .filled(piece.shape.blockColor)
            }
        }
        currentPiece = nil
    }

    private func clearLines() {
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
            if isColliding() {
                state = .gameOver
            }
        }
        spawnNextPiece()
    }

    // MARK: - Render

    private func render() {
        let state = GameSessionState(
            grid: grid,
            currentPiece: currentPiece,
            currentX: currentX,
            currentY: currentY,
            nextPiece: nextPiece,
            score: score,
            level: level,
            state: state
        )
        onRender(state)
    }

    private func finish() {
        render()
        onGameOver()
        doneSemaphore.signal()
    }
}
