// Terminal.swift - Console UI module

import Darwin
import Foundation
import Model

// MARK: - Terminal Control

public struct Terminal {
    public static let clear = "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    public static let home = "\u{001B}[H"
    public static let eraseDown = "\u{001B}[0J"
    public static let hideCursor = "\u{001B}[?25l"
    public static let showCursor = "\u{001B}[?25h"
    public static let reset = "\u{001B}[0m"
    public static let bold = "\u{001B}[1m"

    public static func getTerminalSize() -> (rows: Int, cols: Int) {
        var w = winsize()
        if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0 {
            return (rows: Int(w.ws_row), cols: Int(w.ws_col))
        }
        return (rows: 24, cols: 80)
    }

    public static func cursorPosition(row: Int, col: Int) -> String {
        return "\u{001B}[\(row);\(col)H"
    }
}

// MARK: - TerminalOperations Protocol

public protocol TerminalOperations {
    var clear: String { get }
    var home: String { get }
    var eraseDown: String { get }
    var hideCursor: String { get }
    var showCursor: String { get }
    var reset: String { get }
    var bold: String { get }
    func getTerminalSize() -> (rows: Int, cols: Int)
    func cursorPosition(row: Int, col: Int) -> String
}

public struct TerminalAdapter: TerminalOperations {
    public func getTerminalSize() -> (rows: Int, cols: Int) {
        Terminal.getTerminalSize()
    }

    public func cursorPosition(row: Int, col: Int) -> String {
        Terminal.cursorPosition(row: row, col: col)
    }

    public var clear: String { Terminal.clear }
    public var home: String { Terminal.home }
    public var eraseDown: String { Terminal.eraseDown }
    public var hideCursor: String { Terminal.hideCursor }
    public var showCursor: String { Terminal.showCursor }
    public var reset: String { Terminal.reset }
    public var bold: String { Terminal.bold }

    public init() {}
}

// MARK: - ConsoleRenderer

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
        if let next = data.nextPiece {
            output += terminal.cursorPosition(row: startRow, col: nextCol)
            output += terminal.bold + "Next:" + terminal.reset
            for y in 0..<4 {
                output += terminal.cursorPosition(row: startRow + y + 1, col: nextCol)
                for x in 0..<4 {
                    var hasBlock = false
                    for (px, py) in next.getAbsoluteCoordinates(xOffset: 0, yOffset: 0) {
                        if px == x && py == y {
                            hasBlock = true
                            break
                        }
                    }
                    if hasBlock {
                        output += next.shape.blockColor.ansiCode + "██" + terminal.reset
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
                } else if let piece = data.currentPiece {
                    for (px, py) in piece.getAbsoluteCoordinates(xOffset: data.currentX, yOffset: data.currentY) {
                        if px == x && py == y {
                            color = piece.shape.blockColor
                            break
                        }
                    }
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
            statusText = "GAME OVER - Press q to quit"
        }

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

        return output
    }
}

// MARK: - ConsoleInputHandler

class ConsoleInputHandler: @unchecked Sendable {
    private let inputQueue = DispatchQueue(label: "input.queue")
    private var originalTermios = termios()
    private var running = false

    private weak var inputReceiver: InputReceiver?

    func setInputReceiver(_ receiver: InputReceiver) {
        self.inputReceiver = receiver
    }

    init() {
        enableRawMode()
    }

    deinit {
        disableRawMode()
    }

    func start() {
        running = true
        inputQueue.async { [weak self] in
            guard let self = self else { return }
            while self.running {
                var byte: UInt8 = 0
                let n = read(STDIN_FILENO, &byte, 1)
                if n == 1 {
                    self.processByte(byte)
                }
                usleep(10000)
            }
        }
    }

    func stop() {
        running = false
    }

    private func processByte(_ byte: UInt8) {
        let scalar = UnicodeScalar(byte)
        let char = Character(scalar)

        switch char {
        case "j": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.moveLeft) }
        case "l": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.moveRight) }
        case "k": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.rotate) }
        case " ": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.hardDrop) }
        case "\u{1b}": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.togglePause) }
        case "q": Task.detached { [weak self] in await self?.inputReceiver?.enqueue(.quit) }
        default: break
        }
    }

    private func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL) | UInt(BRKINT) | UInt(INPCK) | UInt(ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)
        raw.c_cc.16 = 1  // VMIN
        raw.c_cc.17 = 0  // VTIME
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    private func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }
}

// MARK: - ConsoleGameUI Facade

public final class ConsoleGameUI: @unchecked Sendable {
    private let controller: GameController
    private let input: ConsoleInputHandler

    public init() {
        let renderer = ConsoleRenderer(terminal: TerminalAdapter())
        self.input = ConsoleInputHandler()

        self.controller = GameController(
            onRender: { state in
                let output = renderer.render(data: state)
                print(output, terminator: "")
                fflush(stdout)
            },
            onGameOver: {
                print(Terminal.showCursor)
                fflush(stdout)
            }
        )

        input.setInputReceiver(controller)
    }

    public func run() {
        print(Terminal.hideCursor)
        print(Terminal.clear)
        fflush(stdout)

        input.start()
        Task.detached { await self.controller.start() }

        // Block until game over
        controller.doneSemaphore.wait()
        input.stop()
    }
}
