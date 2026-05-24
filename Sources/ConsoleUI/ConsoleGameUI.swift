// ConsoleGameUI.swift - Facade integrating controller, renderer, and input handler

import Foundation
import TetrisCore
import os

public final class ConsoleGameUI: @unchecked Sendable {
    private var input: ConsoleInputHandler?
    private let logger: Logger
    private let playerName: String?

    public init(logger: Logger = Logger(), playerName: String? = nil) {
        self.input = ConsoleInputHandler()
        self.logger = logger
        self.playerName = playerName
    }

    public func run(logLevel: LogLevel? = nil) async {
        print(Terminal.hideCursor)
        print(Terminal.clear)
        fflush(stdout)

        input?.start()

        let renderer = ConsoleRenderer(terminal: TerminalAdapter())
        let scoreStorage = ScoreStorage()
        let settings = PersistentGameSettings()
        if let playerName {
            settings.playerName = playerName
        }

        let doneSemaphore = DispatchSemaphore(value: 0)

        let controller = GameController(
            logger: logger,
            logLevel: logLevel,
            scoreStorage: scoreStorage,
            settings: settings
        )
        input?.setInputReceiver(controller)
        input?.onExit = { doneSemaphore.signal() }

        let outputQueue = DispatchQueue(label: "tetris.output")

        // Accumulated state with all required fields — merged from tick diffs.
        var acc = AccumulatedState()

        var tasks: [Task<Void, Never>] = []

        tasks.append(Task {
            for await events in controller.tick {
                if !events.isEmpty {
                    logger.debug("[Tick] \(events.map(\.label).sorted().formatted(), privacy: .public)")
                }
                acc.apply(events)
                input?.currentDisplayState = acc.displayState
                let output = renderer.render(data: acc.snapshot())
                outputQueue.async {
                    print(output, terminator: "")
                    fflush(stdout)
                }
            }
        })

        await controller.start()

        // Wait for game over
        await withUnsafeContinuation { (continuation: UnsafeContinuation<Void, Never>) in
            DispatchQueue.global().async {
                doneSemaphore.wait()
                continuation.resume()
            }
        }

        // Cancel stream tasks and release controller
        tasks.forEach { $0.cancel() }

        // Final cleanup
        input?.stop()
        input?.cleanup()
        input = nil
        print(Terminal.clear)
        print(Terminal.showCursor)
        fflush(stdout)
    }
}

// MARK: - Logging extension

extension GameEvent {
    /// Short label for logging — omits associated values.
    var label: String {
        switch self {
        case .grid:             "grid"
        case .pieceBlocks(_, _, let d): "piece" + (d.map { "↓\(String(format: "%.2f", $0))s" } ?? "")
        case .nextPieceBlocks:  "next"
        case .score(let v):     "score(\(v))"
        case .level(let v):     "level(\(v))"
        case .linesCleared(let v, let rows, let d): "lines(\(v))" + (rows.isEmpty ? "" : " rows:\(rows.sorted()) ↓\(String(format: "%.2f", d))s")
        case .state(let v):     "state(\(v))"
        case .topScores(let v): "scores(\(v.count))"
        case .gridSize(let w, let h): "gridSize(\(w)×\(h))"
        case .playerName(let v): "player(\(v))"
        }
    }
}

/// Non-optional accumulated state built from tick events.
private struct AccumulatedState {
    var grid: [PieceCoordinate: TetrominoColor] = [:]
    var pieceCoords: Set<PieceCoordinate> = []
    var pieceColor: TetrominoColor = .red
    var nextCoords: Set<PieceCoordinate> = []
    var nextColor: TetrominoColor = .red
    var score = 0
    var level = 1
    var linesCleared = 0
    var displayState: GameDisplayState = .playing
    var topScores: [StoredScore] = []
    var gridSize: (width: Int, height: Int) = (10, 20)
    var playerName = ""
    var hardDropDuration: TimeInterval?
    var clearedRows: Set<Int> = []
    var clearedRowsAnimationDuration: TimeInterval = 0

    mutating func apply(_ events: Set<GameEvent>) {
        for event in events {
            switch event {
            case .grid(let v):        grid = v
            case .pieceBlocks(let v, let c, let d): pieceCoords = v; pieceColor = c; hardDropDuration = d
            case .nextPieceBlocks(let v, let c): nextCoords = v; nextColor = c
            case .score(let v):       score = v
            case .level(let v):       level = v
            case .linesCleared(let v, let rows, let d): linesCleared = v; clearedRows = rows; clearedRowsAnimationDuration = d
            case .state(let v):       displayState = v
            case .topScores(let v):   topScores = v
            case .gridSize(let w, let h): gridSize = (w, h)
            case .playerName(let v):  playerName = v
            }
        }
    }

    func snapshot() -> RenderSnapshot {
        RenderSnapshot(
            grid: grid,
            gridSize: gridSize,
            pieceCoords: pieceCoords,
            pieceColor: pieceColor,
            nextCoords: nextCoords,
            nextColor: nextColor,
            score: score,
            level: level,
            linesCleared: linesCleared,
            displayState: displayState,
            topScores: topScores,
            playerName: playerName,
            hardDropDuration: hardDropDuration,
            clearedRows: clearedRows,
            clearedRowsAnimationDuration: clearedRowsAnimationDuration
        )
    }
}

/// Complete state snapshot for rendering — all fields non-optional.
public struct RenderSnapshot {
    let grid: [PieceCoordinate: TetrominoColor]
    let gridSize: (width: Int, height: Int)
    let pieceCoords: Set<PieceCoordinate>
    let pieceColor: TetrominoColor
    let nextCoords: Set<PieceCoordinate>
    let nextColor: TetrominoColor
    let score: Int
    let level: Int
    let linesCleared: Int
    let displayState: GameDisplayState
    let topScores: [StoredScore]
    let playerName: String
    let hardDropDuration: TimeInterval?
    let clearedRows: Set<Int>
    let clearedRowsAnimationDuration: TimeInterval
}
