# Tetris

A modular, UI-agnostic Tetris game engine written in Swift. Ships with a console-based reference UI and is designed to be embedded in macOS and iOS applications via Swift Package Manager.

## Architecture

The project is split into three targets with strict layer separation:

```
┌─────────────────────────────────────────────┐
│  tetris (executable)                        │
│  CLI entry point with swift-argument-parser │
├─────────────────────────────────────────────┤
│  ConsoleUI (macOS only)                     │
│  Reference terminal implementation          │
│  ─ ConsoleRenderer (ANSI rendering)         │
│  ─ ConsoleInputHandler (raw mode stdin)     │
│  ─ ColorPalette (ANSI color mapping)        │
├─────────────────────────────────────────────┤
│  TetrisCore (macOS + iOS)                   │
│  UI-agnostic game engine                    │
│  ─ GameController (actor)                   │
│  ─ GameEvent (diff-style event enum)        │
│  ─ Tetromino, TetrominoShape definitions    │
│  ─ ScoreStorage (JSON persistence)          │
│  ─ InputReceiver / KeyEvent protocol        │
└─────────────────────────────────────────────┘
```

**Key design decisions:**

- **Actor-based concurrency**: `GameController` is a Swift `actor`, providing data-race-free access to game state across concurrent contexts. All state mutations are serialized through the actor's executor.
- **Event-driven input**: An internal `InputBuffer` actor decouples input production from consumption. UI layers send `KeyEvent` values via `enqueue(_:)`, and the game loop processes them sequentially.
- **Diff-style tick stream**: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>` — each tick yields a set of `GameEvent` values for only the changed fields. Absence from the set means unchanged. Consumers accumulate state by switching over events.
- **Validated state machine**: All `GameState` transitions go through a `transition(to:)` method backed by a `validTransitions` table. Invalid transitions are silently rejected — the state graph is defined in one place, not scattered across call sites.
- **Timer lifecycle in didSet**: Drop and lock timers are started/stopped exclusively in `state.didSet`, ensuring consistent lifecycle management regardless of which code path triggers the transition.
- **Color abstraction**: `TetrominoColor` (in TetrisCore) is a UI-agnostic color enum. Each renderer maps it to its own color system — `ColorPalette` does this for ANSI consoles, a native app would map it to `UIColor`/`NSColor`.

## Console UI (Reference Implementation)

### Build & Run

```bash
# Build and run with default settings
swift run

# Build release binary
swift build -c release
./.build/release/tetris

# With debug logging and custom player name
swift run tetris -d debug -u Alice
```

### Controls

| Key | Action |
|-----|--------|
| `j` | Move left |
| `l` | Move right |
| `k` | Rotate |
| `Space` | Hard drop / Start new game |
| `Esc` | Pause / Resume / Exit from game over |
| `q` | Quit to game over screen |

### CLI Options

| Flag | Description |
|------|-------------|
| `-d, --debug <level>` | Log level: `debug`, `info`, `notice`, `error`, `fault` |
| `-u, --user <name>` | Player name (persisted to `~/.tetris/settings.json`) |

### Run Tests

```bash
swift test
```

## Using TetrisCore as an SPM Dependency

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/maxshevelev/VibeTetris", from: "0.1.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "TetrisCore", package: "tetris"),
        ]
    ),
]
```

Or add directly through Xcode: `File → Add Package Dependencies...` → paste `https://github.com/maxshevelev/VibeTetris` → select `TetrisCore`.

## API Reference

### `GameController` (actor)

The central game engine. Create one instance per game session.

```swift
public actor GameController: InputReceiver
```

#### Initialization

```swift
public init(
    logger: Logger = Logger(),
    logLevel: LogLevel? = nil,
    scoreStorage: ScoreStorage = ScoreStorage(),
    playerName: String = defaultPlayerName(),
    onGameFinished: @escaping @Sendable () -> Void
)
```

| Parameter | Description |
|-----------|-------------|
| `logger` | Apple `os.Logger` instance for debug output |
| `logLevel` | Optional minimum log level for filtering |
| `scoreStorage` | Backend for persisting top scores to JSON |
| `playerName` | Display name for score tracking |
| `onGameFinished` | Called when the player exits the game via ESC from game over |

#### Update Stream

`GameController` exposes a single `AsyncStream` that carries diff-style updates:

```swift
nonisolated public let tick: AsyncStream<Set<GameEvent>>
```

Each tick yields a `Set<GameEvent>` containing only the values that changed since the previous tick. Absence from the set means unchanged. The initial tick sends all fields.

| Event | Type | Emits when |
|-------|------|------------|
| `.grid` | `[[BlockState]]` | Piece locks, lines are cleared |
| `.pieceBlocks` | `[PieceBlock]` | Every tick, move, rotate (current piece position) |
| `.nextPieceBlocks` | `[PieceBlock]` | Piece locks (new next piece generated) |
| `.score` | `Int` | Lines are cleared |
| `.level` | `Int` | Level advances |
| `.linesCleared` | `Int` | Lines are cleared |
| `.state` | `GameDisplayState` | Pause, resume, game over, restart |
| `.topScores` | `[StoredScore]` | Game over (new score saved) |
| `.playerName` | `String` | Game starts |

Consumers accumulate state by switching over events:

```swift
Task {
    for await events in controller.tick {
        for event in events {
            switch event {
            case .grid(let g):  renderGrid(g)
            case .score(let s): renderScore(s)
            default: break
            }
        }
    }
}
```

#### Methods

```swift
/// Start the game. Begins the drop timer and input listener.
public func start()

/// Send a key event for processing.
/// - Parameter event: The KeyEvent to enqueue.
public func enqueue(_ event: KeyEvent) async
```

The `InputReceiver` protocol:

```swift
public protocol InputReceiver: AnyObject & Sendable {
    func enqueue(_ event: KeyEvent) async
}
```

### `KeyEvent`

Input events recognized by the game engine.

```swift
public enum KeyEvent: Sendable {
    case moveLeft
    case moveRight
    case rotate
    case hardDrop
    case esc
    case quit
}
```

- `esc` toggles pause/resume during play and exits to main menu from game over.
- `quit` immediately ends the game (triggers game over and score save).
- `hardDrop` also functions as "start new game" when in the game over state.

---

### `PieceBlock`

A single block within the active or preview piece.

```swift
public struct PieceBlock {
    public let x: Int
    public let y: Int
    public let color: TetrominoColor
}
```

Note: Coordinates are relative to the grid for `pieceBlocks` and relative to the preview box (0–3) for `nextPieceBlocks`.

---

### `GameDisplayState`

Consumer-facing game state. Internal timer states like `.dropping` and `.locking` are collapsed into `.playing`.

```swift
public enum GameDisplayState: Sendable {
    case playing   // Game is active — render the board and accept input
    case paused    // Game is paused — show a pause overlay
    case gameOver  // Game is over — show score summary
}
```

---

### `BlockState`

```swift
public enum BlockState: Equatable {
    case empty
    case filled(TetrominoColor)

    public var isFilled: Bool
    public var color: TetrominoColor?
}
```

---

### `Tetromino` & `TetrominoShape`

Immutable tetromino piece with rotation support.

```swift
public struct Tetromino: Sendable {
    public let shape: TetrominoShape

    public init(shape: TetrominoShape, rotationIndex: Int = 0)

    /// Current block coordinates relative to piece origin.
    public var blocks: [[Int]]

    /// Block coordinates offset by (x, y) on the grid.
    public func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(x: Int, y: Int)]

    /// Return a new Tetromino rotated by `offset` 90° steps.
    public func rotated(by offset: Int) -> Tetromino
}

public enum TetrominoShape: String, Sendable {
    case I, O, T, S, Z, J, L

    public var blockColor: TetrominoColor
}
```

---

### `TetrominoColor`

UI-agnostic color identifiers for tetromino pieces.

```swift
public enum TetrominoColor: Sendable {
    case cyan    // I piece
    case yellow  // O piece
    case magenta // T piece
    case green   // S piece
    case red     // Z piece
    case blue    // J piece
    case orange  // L piece
}
```

---

### `ScoreStorage` & `StoredScore`

Persistent top-10 score storage backed by a local JSON file.

```swift
public struct StoredScore: Codable, Equatable {
    public let playerName: String
    public let score: Int
    public let level: Int

    public init(playerName: String = defaultPlayerName(), score: Int, level: Int)
}

public final class ScoreStorage: Sendable {
    /// Default path: ~/.tetris/scores.json
    /// On iOS, pass an app-sandbox path via filePath.
    public init(filePath: URL? = nil)

    @discardableResult
    public func add(score: Int, level: Int, playerName: String = defaultPlayerName()) -> [StoredScore]

    public func topScores() -> [StoredScore]
}
```

On iOS, provide a sandbox-relative path:

```swift
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let scoresPath = documents.appendingPathComponent("scores.json")
let storage = ScoreStorage(filePath: scoresPath)
```

---

### `LogLevel`

```swift
public enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, notice, error, fault

    public func allows(_ level: LogLevel) -> Bool
}
```

A level permits messages at itself and higher (debug < info < notice < error < fault).

---

### Player Name Utilities

```swift
/// Returns persisted player name from ~/.tetris/settings.json,
/// or the system username as fallback.
public func defaultPlayerName() -> String

/// Persist a player name to ~/.tetris/settings.json.
public func storePlayerName(_ name: String)
```

## Scoring

Classical Tetris scoring formula:

| Lines cleared | Base score |
|---------------|------------|
| 1 (Single)    | 40 |
| 2 (Double)    | 100 |
| 3 (Triple)    | 300 |
| 4 (Tetris)    | 1200 |

**Final score = base × (level + 1)**

Level advances every 10 lines cleared, up to a maximum of level 10. Drop speed increases with level (`0.8s` → `0.15s` minimum interval).

## Persistent Data

| File | Path | Content |
|------|------|---------|
| Scores | `~/.tetris/scores.json` | Top 10 scores with player name and level |
| Settings | `~/.tetris/settings.json` | Player name preference |

On iOS, provide custom paths via `ScoreStorage(filePath:)` and `storePlayerName()`.
