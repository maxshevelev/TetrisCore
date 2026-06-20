// ConsoleGameUI.swift - Facade integrating controller, renderer, and input handler

import Foundation
import TetrisCore
import os

public final class ConsoleGameUI: @unchecked Sendable {
    private let logger: Logger
    private let playerName: String?

    public init(logger: Logger = Logger(), playerName: String? = nil) {
        self.logger = logger
        self.playerName = playerName
    }

    public func run(logLevel: LogLevel? = nil) async {
        print(Terminal.hideCursor)
        print(Terminal.clear)
        fflush(stdout)

        let input = ConsoleInputHandler()
        input.start()

        // Create the exit signal after the handler is fully initialized
        let exitStream = AsyncStream<Void> { input.exitContinuation = $0 }

        let renderer = ConsoleRenderer(terminal: TerminalAdapter())
        let scoreStorage = ScoreStorage()
        let settings = PersistentGameSettings()
        if let playerName {
            settings.playerName = playerName
        }

        let controller = GameController(
            logger: logger,
            logLevel: logLevel,
            scoreStorage: scoreStorage,
            settings: settings
        )
        input.setInputReceiver(controller)

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
                input.currentDisplayState = acc.displayState
                let output = renderer.render(data: acc.snapshot())
                outputQueue.async {
                    print(output, terminator: "")
                    fflush(stdout)
                }
            }
        })

        await controller.start()

        // Wait for game over via async flow
        await exitStream.first(where: { _ in true })

        // Cancel stream tasks
        tasks.forEach { $0.cancel() }

        // Final cleanup
        input.stop()
        input.cleanup()
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
        case .pieceBlocks(_, _, let d): "piece" + (d.map { "←\(String(format: "%.2f", $0))s" } ?? "")
        case .nextPieceBlocks:  "next"
        case .score(let v):     "score(\(v))"
        case .level(let v):     "level(\(v))"
        case .linesCleared(let v, let rows, let d): "lines(\(v))" + (rows.isEmpty ? "" : " rows:\(rows.sorted()) ←\(String(format: "%.2f", d))s")
        case .state(let v):     "state(\(v))"
        case .topScores(let v): "scores(\(v.count))"
        case .playerName(let v): "player(\(v))"
        case .gridSize(let w, let h): "gridSize(\(w)x\(h))"
        case .ghostPieceBlocks: "ghost"
        case .newPiece:         "newPiece"
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
    var playerName = ""
    var gridWidth = 10
    var gridHeight = 20
    var ghostPieceCoords: Set<PieceCoordinate> = []
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
            case .playerName(let v):  playerName = v
            case .gridSize(let w, let h): gridWidth = w; gridHeight = h
            case .ghostPieceBlocks(let v): ghostPieceCoords = v
            case .newPiece: break // signal-only — no accumulated state
            }
        }
    }

    func snapshot() -> RenderSnapshot {
        RenderSnapshot(
            grid: grid,
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
            gridWidth: gridWidth,
            gridHeight: gridHeight,
            ghostPieceCoords: ghostPieceCoords,
            hardDropDuration: hardDropDuration,
            clearedRows: clearedRows,
            clearedRowsAnimationDuration: clearedRowsAnimationDuration
        )
    }
}

/// Complete state snapshot for rendering — all fields non-optional.
public struct RenderSnapshot {
    let grid: [PieceCoordinate: TetrominoColor]
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
    let gridWidth: Int
    let gridHeight: Int
    let ghostPieceCoords: Set<PieceCoordinate>
    let hardDropDuration: TimeInterval?
    let clearedRows: Set<Int>
    let clearedRowsAnimationDuration: TimeInterval
}
