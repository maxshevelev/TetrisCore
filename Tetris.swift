import Foundation
import Darwin

// MARK: - Terminal Colors
struct Terminal {
    static let clear = "\u{001B}[H\u{001B}[2J\u{001B}[3J"
    static let home = "\u{001B}[H"
    static let eraseDown = "\u{001B}[0J"
    static let hideCursor = "\u{001B}[?25l"
    static let showCursor = "\u{001B}[?25h"
    static let reset = "\u{001B}[0m"
    static let bold = "\u{001B}[1m"

    static let cyan = "\u{001B}[36m"
    static let yellow = "\u{001B}[33m"
    static let magenta = "\u{001B}[35m"
    static let green = "\u{001B}[32m"
    static let red = "\u{001B}[31m"
    static let blue = "\u{001B}[34m"
    static let orange = "\u{001B}[38;5;208m"
}

func getTerminalSize() -> (rows: Int, cols: Int) {
    var w = winsize()
    if ioctl(STDOUT_FILENO, UInt(TIOCGWINSZ), &w) == 0 {
        return (rows: Int(w.ws_row), cols: Int(w.ws_col))
    }
    return (rows: 24, cols: 80)
}

func cursorPosition(row: Int, col: Int) -> String {
    return "\u{001B}[\(row);\(col)H"
}

// MARK: - Tetromino Shapes
enum TetrominoShape {
    case I, O, T, S, Z, J, L

    var color: String {
        switch self {
        case .I: return Terminal.cyan
        case .O: return Terminal.yellow
        case .T: return Terminal.magenta
        case .S: return Terminal.green
        case .Z: return Terminal.red
        case .J: return Terminal.blue
        case .L: return Terminal.orange
        }
    }

    var blocks: [[[Int]]] {
        switch self {
        case .I:
            return [
                [[0, 1], [1, 1], [2, 1], [3, 1]],
                [[1, 0], [1, 1], [1, 2], [1, 3]]
            ]
        case .O:
            return [[[1, 0], [2, 0], [1, 1], [2, 1]]]
        case .T:
            return [
                [[1, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [1, 1], [2, 1], [1, 2]],
                [[0, 1], [1, 1], [2, 1], [1, 2]],
                [[1, 0], [0, 1], [1, 1], [1, 2]]
            ]
        case .S:
            return [
                [[1, 0], [2, 0], [0, 1], [1, 1]],
                [[1, 0], [1, 1], [2, 1], [2, 2]]
            ]
        case .Z:
            return [
                [[0, 0], [1, 0], [1, 1], [2, 1]],
                [[2, 0], [1, 1], [2, 1], [1, 2]]
            ]
        case .J:
            return [
                [[0, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [2, 0], [1, 1], [1, 2]],
                [[0, 1], [1, 1], [2, 1], [2, 2]],
                [[1, 0], [1, 1], [1, 2], [0, 2]]
            ]
        case .L:
            return [
                [[2, 0], [0, 1], [1, 1], [2, 1]],
                [[1, 0], [1, 1], [1, 2], [2, 2]],
                [[0, 1], [1, 1], [2, 1], [0, 2]],
                [[0, 0], [1, 0], [1, 1], [1, 2]]
            ]
        }
    }
}

// MARK: - Tetromino
class Tetromino {
    let shape: TetrominoShape
    var rotationIndex = 0

    init(shape: TetrominoShape) {
        self.shape = shape
    }

    func getBlocks() -> [[Int]] {
        let rotations = shape.blocks
        return rotations[(rotationIndex % rotations.count + rotations.count) % rotations.count]
    }

    func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(x: Int, y: Int)] {
        return getBlocks().map { block in
            (x: xOffset + block[0], y: yOffset + block[1])
        }
    }

    func rotate() {
        rotationIndex -= 1
    }

    func rotateBack() {
        rotationIndex += 1
    }
}

// MARK: - Game Engine
class TetrisGame {
    let width = 10
    let height = 20
    var grid: [[String]] = []
    var currentPiece: Tetromino?
    var nextPiece: Tetromino?
    var currentX = 0
    var currentY = 0
    var score = 0
    var linesCleared = 0
    var gameOver = false
    var paused = false
    var pieceColor = ""
    var lastDropTime = Date()
    var lockTime: Date?
    let lockDelay: TimeInterval = 0.4

    var level: Int {
        min(10, max(1, linesCleared / 10 + 1))
    }

    var dropInterval: TimeInterval {
        max(0.15, 0.8 - Double(level - 1) * 0.06)
    }

    init() {
        grid = Array(repeating: Array(repeating: "", count: width), count: height)
        spawnNextPiece()
        spawnNewPiece()
    }

    private func spawnNextPiece() {
        let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
        let shape = shapes.randomElement()!
        nextPiece = Tetromino(shape: shape)
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
                grid[y][x] = pieceColor
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
        let terminalSize = getTerminalSize()
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
            output += cursorPosition(row: startRow, col: nextCol)
            output += Terminal.bold + "Next:" + Terminal.reset
            for y in 0..<4 {
                output += cursorPosition(row: startRow + y + 1, col: nextCol)
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

        output += cursorPosition(row: startRow, col: startCol)
        output += Terminal.bold + "╔" + String(repeating: "═", count: width * 2) + "╗" + Terminal.reset

        for y in 0..<height {
            output += cursorPosition(row: startRow + y + 1, col: startCol)
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

        output += cursorPosition(row: startRow + height + 1, col: startCol)
        output += Terminal.bold + "╚" + String(repeating: "═", count: width * 2) + "╝" + Terminal.reset

        func centerColumn(for text: String) -> Int {
            return startCol + max(0, (boardWidth - text.count) / 2)
        }

        let scoreText = "Score: \(score)  Level: \(level)"
        let controlsText = "Controls: j=left  k=rotate  l=right  SPACE=drop  q=quit"
        let statusText = paused ? "PAUSED - Press ESC to resume" : "Drop: \(String(format: "%.2fs", dropInterval))"

        output += cursorPosition(row: startRow + height + 3, col: centerColumn(for: scoreText))
        output += "Score: " + Terminal.bold + String(score) + Terminal.reset + "  Level: " + Terminal.bold + String(level) + Terminal.reset

        output += cursorPosition(row: startRow + height + 4, col: centerColumn(for: controlsText))
        output += controlsText

        output += cursorPosition(row: startRow + height + 5, col: centerColumn(for: statusText))
        if paused {
            output += Terminal.bold + Terminal.red + statusText + Terminal.reset
        } else {
            output += statusText
        }

        print(output, terminator: "")
        fflush(stdout)
    }
}

// MARK: - Non-blocking input
class InputHandler {
    var lastChar: Character?
    let inputQueue = DispatchQueue(label: "input.queue")
    var originalTermios = termios()

    init() {
        enableRawMode()
        startListening()
    }

    deinit {
        disableRawMode()
        print(Terminal.showCursor)
    }

    func enableRawMode() {
        tcgetattr(STDIN_FILENO, &originalTermios)
        var raw = originalTermios
        raw.c_lflag &= ~(UInt(ECHO) | UInt(ICANON) | UInt(ISIG) | UInt(IEXTEN))
        raw.c_iflag &= ~(UInt(IXON) | UInt(ICRNL) | UInt(BRKINT) | UInt(INPCK) | UInt(ISTRIP))
        raw.c_oflag &= ~(UInt(OPOST))
        raw.c_cflag |= UInt(CS8)
        raw.c_cc.16 = 1
        raw.c_cc.17 = 0
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
    }

    func disableRawMode() {
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &originalTermios)
    }

    func startListening() {
        inputQueue.async {
            while true {
                var byte: UInt8 = 0
                let n = read(STDIN_FILENO, &byte, 1)
                if n == 1 {
                    let scalar = UnicodeScalar(byte)
                    self.lastChar = Character(scalar)
                }
                usleep(10000)
            }
        }
    }

    func getInput() -> Character? {
        let input = lastChar
        lastChar = nil
        return input
    }
}

// MARK: - Main
func main() {
    let inputHandler = InputHandler()
    let game = TetrisGame()

    print(Terminal.hideCursor)
    print(Terminal.clear)

    while !game.gameOver {
        if let input = inputHandler.getInput() {
            switch input {
            case "j": game.moveLeft()
            case "k": game.rotatePiece()
            case "l": game.moveRight()
            case " ": game.hardDrop()
            case "\u{1b}": game.paused.toggle()
            case "q": game.gameOver = true
            default: break
            }
        }

        if !game.paused {
            game.update()
        }
        game.render()
        usleep(40000)
    }

    inputHandler.disableRawMode()
    print(Terminal.showCursor)
}

main()
