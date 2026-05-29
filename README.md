# Tetris

A modular, UI-agnostic Tetris game engine written in Swift. Ships with a console-based reference UI and is designed to be embedded in macOS and iOS applications via Swift Package Manager.

## Architecture

The project is split into three targets with strict layer separation:

```
┌──────────────────────────────────┐
│  tetris (executable)             │
│  CLI entry point                 │
│  with swift-argument-parser      │
├──────────────────────────────────┤
│  ConsoleUI (macOS only)          │
│  Reference terminal implementation │
│  ─ ConsoleRenderer (ANSI rendering) │
│  ─ ConsoleInputHandler (raw mode) │
│  ─ ColorPalette (ANSI color mapping) │
├──────────────────────────────────┤
│  TetrisCore (macOS + iOS)        │
│  UI-agnostic game engine         │
│  ─ GameController (actor)        │
│  ─ GameEvent (diff-style events) │
│  ─ Tetromino, TetrominoShape     │
│  ─ ScoreStorage (JSON persistence) │
│  ─ InputReceiver / ControlEvent   │
│  ─ GameSettings / GameState      │
└──────────────────────────────────┘
```

**Key design decisions:**

- **Actor-based concurrency**: `GameController` is a Swift `actor`, providing data-race-free access to game state across concurrent contexts. All state mutations are serialized through the actor's executor.
- **Event-driven input**: An internal `InputBuffer` actor decouples input production from consumption. UI layers send `ControlEvent` values via `enqueue(_:)`, and the game loop processes them sequentially.
- **Diff-style tick stream**: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>` — each tick yields a set of changed fields. Absence from the set means unchanged. Consumers accumulate state by switching over events.
- **Validated state machine**: All `GameState` transitions go through a `transition(to:)` method backed by a `validTransitions` table. Invalid transitions are silently rejected — the state graph is defined in one place.
- **Timer lifecycle in didSet**: Drop and lock timers are started/stopped exclusively in `state.didSet`, ensuring consistent lifecycle management.
- **Color abstraction**: `TetrominoColor` (in TetrisCore) is a UI-agnostic color enum. Each renderer maps it to its own color system — `ColorPalette` does this for ANSI consoles, a native app would map it to `UIColor`/`NSColor`.
- **Sparse grid**: The game grid uses `[PieceCoordinate: TetrominoColor]` — only filled cells are stored. An empty board has zero entries. Iteration cost is proportional to filled cells, not grid size.

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

| Key | Playing | Paused | Game Over |
|-----|---------|--------|-----------|
| `j` | Move left | — | — |
| `l` | Move right | — | — |
| `k` | Rotate (CCW) | — | — |
| `Space` | Hard drop | Resume | New game |
| `Esc` | Pause | Resume | — |
| `q` | Stop | — | Exit |

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
    .package(url: "https://github.com/maxshevelev/TetrisCore", from: "0.2.0"),
],
targets: [
    .target(
        name: "YourTarget",
        dependencies: [
            .product(name: "TetrisCore", package: "TetrisCore"), // Game engine
            .product(name: "ConsoleUI", package: "TetrisCore"), // macOS only
        ]
    ),
]
```

### `TetrisCore` Only

If you only want the game engine (for a native macOS/iOS implementation):

```swift
.dependencies: [
    .product(name: "TetrisCore", package: "TetrisCore"),
]
```

### Xcode

Add directly through Xcode: `File → Add Package Dependencies...` → paste `https://github.com/maxshevelev/TetrisCore` → select `TetrisCore` and `ConsoleUI`.

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
    settings: any GameSettings = PersistentGameSettings()
)
```

| Parameter | Description |
|-----------|-------------|
| `logger` | Apple `os.Logger` instance for debug output |
| `logLevel` | Optional minimum log level for filtering |
| `scoreStorage` | Backend for persisting top scores to JSON |
| `settings` | Runtime settings via `GameSettings` protocol (see below). Defaults to `PersistentGameSettings`. |

#### Update Stream

`GameController` exposes a single `AsyncStream` that carries diff-style updates:

```swift
nonisolated public let tick: AsyncStream<Set<GameEvent>>
```

Each tick yields a `Set<GameEvent>` containing only the changed fields. Absence from the set means unchanged. The initial tick sends all fields.

| Event | Type | Emits when |
|-------|------|------------|
| `.grid` | `[PieceCoordinate: TetrominoColor]` | Piece locks, lines are cleared. Sparse representation. |
| `.pieceBlocks` | `(Set<PieceCoordinate>, color: TetrominoColor, hardDropDuration: TimeInterval?)` | Every tick, move, rotate (current piece position). `hardDropDuration` is non-nil on hard-drop. |
| `.nextPieceBlocks` | `(Set<PieceCoordinate>, color: TetrominoColor)` | Piece locks (new next piece generated) |
| `.score` | `Int` | Lines are cleared |
| `.level` | `Int` | Level advances |
| `.linesCleared` | `(Int, clearedRows: Set<Int>, animationDuration: TimeInterval)` | Lines cleared. See [Line-Clear Animation](#line-clear-animation) below. |
| `.state` | `GameDisplayState` | Pause, resume, game over, restart |
| `.topScores` | `[StoredScore]` | Game over (new score saved) |
| `.playerName` | `String` | Game starts |
| `.gridSize(width: Int, height: Int)` | | Grid dimensions (sent on first tick) |
| `.ghostPieceBlocks(Set<PieceCoordinate>)` | | Ghost piece enabled (see `isGhostPieceEnabled`) |

### Line-Clear Animation

When `isLineClearAnimated` is `true`, line clearing follows a two-phase sequence:

1. **Pre-clear tick**: `.linesCleared(count, clearedRows: {rowIndices}, animationDuration: dur)` fires alongside a `.grid` snapshot showing the locked piece in the still-full rows. The consumer should animate the rows in `clearedRows` out over `animationDuration` (derived from drop cadence: `min(dropInterval * 0.5, 0.25)`).
2. **Post-clear tick**: After the animation delay, a new `.grid` snapshot fires with the rows removed and the new piece spawned. `.score` and `.linesCleared` update to their new values.

When `isLineClearAnimated` is `false` (console UI default), `clearedRows` is empty and `animationDuration` is zero — the grid updates immediately.

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

#### Properties

```swift
/// Runtime settings — read or modify to change behavior at any time.
public let settings: any GameSettings
```

#### Methods

```swift
/// Start the game. Begins the drop timer and input listener.
public func start()

/// Send a control event for processing.
public func enqueue(_ event: ControlEvent) async
```

### `InputReceiver`

Protocol for receiving input events. Implemented by `GameController`.

```swift
public protocol InputReceiver: AnyObject & Sendable {
    func enqueue(_ event: ControlEvent) async
}
```

### `ControlEvent`

Input events recognized by the game engine. Source-agnostic — can originate from keyboard, gamepad, gestures, etc.

```swift
public enum ControlEvent: Sendable {
    case moveLeft
    case moveRight
    case rotate
    case hardDrop  // Also starts new game when in game over
    case pause
    case resume
    case stop
    case start     // Explicit new game (game over only)
}
```

- `pause` pauses the game (ignored unless playing).
- `resume` resumes the game (ignored unless paused).
- `stop` ends the current game (transitions to game over and saves the score).
- `hardDrop` drops the piece; in game over state it starts a new game.
- `start` starts a new game (only valid in game over state).
- Events that don't match the current game state are silently ignored.

### `GameSettings`

Runtime settings exposed via `controller.settings`. Persisted settings are written to `settings.json` on set.

```swift
public protocol GameSettings: AnyObject, Sendable {
    var playerName: String { get set }
    var lockImmediatelyAfterHardDrop: Bool { get set }
    var isHardDropAnimated: Bool { get set }
    var isLineClearAnimated: Bool { get set }
    var initialLevel: Int { get set }
    var isGhostPieceEnabled: Bool { get set }
    func addListener(_ listener: SettingsUpdateListener)
    func removeListener(_ listener: SettingsUpdateListener)
}

public protocol SettingsUpdateListener: AnyObject, Sendable {
    func settingsDidUpdate(_ settings: any GameSettings)
}
```

| Property | Persisted | Description |
|----------|-----------|-------------|
| `playerName` | Yes | Display name for score tracking. Non-empty validation. |
| `lockImmediatelyAfterHardDrop` | Yes | Piece locks immediately after hard drop (or after animation) |
| `isHardDropAnimated` | Yes | Hard drops add a brief visual delay |
| `isLineClearAnimated` | Yes | Line clears follow a two-phase tick sequence |
| `initialLevel` | Yes | Starting level (1–10, clamped). Default 1 |
| `isGhostPieceEnabled` | Yes | Show ghost piece preview (default true) |

The default implementation is `PersistentGameSettings`, which reads initial values from `settings.json` on init.

### `PieceCoordinate`

A single coordinate within a piece.

```swift
public struct PieceCoordinate: Hashable, Sendable {
    public let x: Int
    public let y: Int
}
```

- For `.pieceBlocks`: grid-absolute coordinates
- For `.nextPieceBlocks`: preview-local (0–3)

### `GameDisplayState`

Consumer-facing game state. Internal timer states (`dropping`, `locking`, `initializing`) are collapsed into `.playing`.

```swift
public enum GameDisplayState: Hashable, Sendable {
    case playing   // Game is active — render the board and accept input
    case paused    // Game is paused — show a pause overlay
    case gameOver  // Game is over — show score summary
}
```

### `Tetromino` & `TetrominoShape`

Immutable tetromino piece with SRS wall-kick rotation.

```swift
public struct Tetromino: Sendable {
    public let shape: TetrominoShape
    public let rotationIndex: Int  // Immutable

    public init(shape: TetrominoShape, rotationIndex: Int = 0)
    
    public var blocks: [[Int]]
    public func getAbsoluteCoordinates(xOffset: Int, yOffset: Int) -> [(x: Int, y: Int)]
    public func rotated(by offset: Int) -> Tetromino
}

public enum TetrominoShape: String, Sendable {
    case I, O, T, S, Z, J, L
    public var blockColor: TetrominoColor
}
```

- `rotationIndex` is `let` (immutable) — use `rotated(by:)` to produce a new `Tetromino`.
- `blocks` is a computed property that returns the shape's block coordinates for the current rotation state.
- `rotated(by:)` returns a **new** `Tetromino` — never mutates in place.

### `TetrominoColor`

UI-agnostic color identifiers for tetromino pieces.

```swift
public enum TetrominoColor: Hashable, Sendable {
    case cyan    // I piece
    case yellow  // O piece
    case magenta // T piece
    case green   // S piece
    case red     // Z piece
    case blue    // J piece
    case orange  // L piece
}
```

### `ScoreStorage` & `StoredScore`

Persistent top-10 score storage backed by a local JSON file.

```swift
public struct StoredScore: Codable, Hashable, Equatable, Sendable {
    public let playerName: String
    public let score: Int
    
    public init(playerName: String = "", score: Int)
}

public final class ScoreStorage: Sendable {
    public init(filePath: URL? = nil)
    @discardableResult
    public func add(score: Int, playerName: String) -> [StoredScore]
    public func topScores() -> [StoredScore]
}
```

Default paths:
- macOS: `~/.tetris/scores.json`
- iOS: `~/Library/Application Support/Tetris/scores.json`

On iOS, provide a sandbox-relative path:

```swift
let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
let scoresPath = documents.appendingPathComponent("scores.json")
let storage = ScoreStorage(filePath: scoresPath)
```

> **Note**: `add()` deduplicates by `(playerName, score)` pair globally. Same player scoring the same value twice in different games will result in the second score being silently dropped. This behavior will be fixed in a future release to use game-scoped deduplication.

### `LogLevel`

```swift
public enum LogLevel: String, CaseIterable, Sendable {
    case debug, info, notice, error, fault
    
    public func allows(_ level: LogLevel) -> Bool
}
```

A level permits messages at itself and higher (debug < info < notice < error < fault).

---

## Scoring

Classical Tetris scoring formula:

| Lines Cleared | Base Score |
|---------------|-----------|
| 1 (Single) | 40 |
| 2 (Double) | 100 |
| 3 (Triple) | 300 |
| 4 (Tetris) | 1200 |

**Final score = base × (level + 1)**

Level advances every 10 lines cleared from `initialLevel` (default 1), capped at 10. Drop speed increases with level (`0.8s` → `0.15s` minimum).

---

## Persistent Data

| File | Path (macOS) | Path (iOS) | Content |
|------|-------------|------------|---------|
| Scores | `~/.tetris/scores.json` | `~/Library/.../Tetris/scores.json` | Top 10 scores with player name |
| Settings | `~/.tetris/settings.json` | `~/Library/.../Tetris/settings.json` | playerName, lockImmediately, animations, ghost piece, initialLevel |
