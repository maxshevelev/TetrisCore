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
│  ─ InputReceiver / ControlEvent protocol    │
└─────────────────────────────────────────────┘
```

**Key design decisions:**

- **Actor-based concurrency**: `GameController` is a Swift `actor`, providing data-race-free access to game state across concurrent contexts. All state mutations are serialized through the actor's executor.
- **Event-driven input**: An internal `InputBuffer` actor decouples input production from consumption. UI layers send `ControlEvent` values via `enqueue(_:)`, and the game loop processes them sequentially.
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
| `Space` | Hard drop / Start new game / Resume |
| `Esc` | Pause / Resume |
| `q` | Stop playing / Exit from game over |

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
    settings: any GameSettings = PersistentGameSettings()
)
```

| Parameter | Description |
|-----------|-------------|
| `logger` | Apple `os.Logger` instance for debug output |
| `logLevel` | Optional minimum log level for filtering |
| `scoreStorage` | Backend for persisting top scores to JSON |
| `settings` | Runtime settings via `GameSettings` protocol (see below). Defaults to `PersistentGameSettings` which reads/writes `settings.json`. |

#### Update Stream

`GameController` exposes a single `AsyncStream` that carries diff-style updates:

```swift
nonisolated public let tick: AsyncStream<Set<GameEvent>>
```

Each tick yields a `Set<GameEvent>` containing only the values that changed since the previous tick. Absence from the set means unchanged. The initial tick sends all fields.

| Event | Type | Emits when |
|-------|------|------------|
| `.grid` | `[[BlockState]]` | Piece locks, lines are cleared |
| `.pieceBlocks` | `([PieceBlock], hardDropDuration: TimeInterval?)` | Every tick, move, rotate (current piece position). The optional `hardDropDuration` is non-nil when the piece position is the result of a hard drop — the consumer should animate the piece falling to this position over the given duration. `nil` means the move was gravity-driven. |
| `.nextPieceBlocks` | `[PieceBlock]` | Piece locks (new next piece generated) |
| `.score` | `Int` | Lines are cleared |
| `.level` | `Int` | Level advances |
| `.linesCleared` | `(Int, clearedRows: Set<Int>, animationDuration: TimeInterval)` | Lines are cleared. See [Line-Clear Animation](#line-clear-animation) below. |
| `.state` | `GameDisplayState` | Pause, resume, game over, restart |
| `.topScores` | `[StoredScore]` | Game over (new score saved) |
| `.playerName` | `String` | Game starts |

### Line-Clear Animation

When `isLineClearAnimated` is `true`, line clearing follows a two-phase sequence:

1. **Pre-clear tick**: `.linesCleared(count, clearedRows: {rowIndices}, animationDuration: dur)` fires alongside a `.grid` snapshot showing the locked piece in the still-full rows. The consumer should animate the rows in `clearedRows` out over `animationDuration` (derived from drop cadence: `min(dropInterval * 0.5, 0.25)`).
2. **Post-clear tick**: After the animation delay, a new `.grid` snapshot fires with the rows removed and the new piece spawned. `.score` and `.linesCleared` update to their new values in this tick.

When `isLineClearAnimated` is `false` (console UI default), `clearedRows` is empty and `animationDuration` is zero — the grid updates immediately with no animation hint.

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
/// Persisted settings (playerName, lockImmediatelyAfterHardDrop) are
/// written to settings.json on set.
public let settings: any GameSettings
```

#### Methods

```swift
/// Start the game. Begins the drop timer and input listener.
public func start()

/// Send a control event for processing.
/// - Parameter event: The ControlEvent to enqueue.
public func enqueue(_ event: ControlEvent) async
```

The `InputReceiver` protocol:

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
    case hardDrop
    case pause
    case resume
    case stop
}
```

- `pause` pauses the game (ignored unless playing).
- `resume` resumes the game (ignored unless paused).
- `stop` ends the current game (transitions to game over and saves the score).
- `hardDrop` also functions as "start new game" when in the game over state.
- Events that don't match the current game state are silently ignored.

---

### `GameSettings`

Runtime settings exposed via `controller.settings`. Persisted settings are written to `settings.json` on set.

```swift
public protocol GameSettings: AnyObject, Sendable {
    var playerName: String { get set }
    var lockImmediatelyAfterHardDrop: Bool { get set }
    var isHardDropAnimated: Bool { get set }
    var isLineClearAnimated: Bool { get set }
    func addListener(_ listener: SettingsUpdateListener)
    func removeListener(_ listener: SettingsUpdateListener)
}

public protocol SettingsUpdateListener: AnyObject, Sendable {
    func settingsDidUpdate(_ settings: any GameSettings)
}
```

| Property | Persisted | Description |
|----------|-----------|-------------|
| `playerName` | Yes | Display name for score tracking |
| `lockImmediatelyAfterHardDrop` | Yes | When `true`, piece locks instantly after hard drop. Default `false`. |
| `isHardDropAnimated` | No | When `true`, hard drops emit a `hardDropDuration` hint on `.pieceBlocks`. |
| `isLineClearAnimated` | No | When `true`, line clears follow a two-phase tick sequence with animation hints. |

The default implementation is `PersistentGameSettings`, which reads initial values from `settings.json` on init.

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

    public init(playerName: String = "", score: Int)
}

public final class ScoreStorage: Sendable {
    /// Default path: ~/.tetris/scores.json on macOS,
    /// ~/Library/Application Support/Tetris/scores.json on iOS.
    /// Pass a custom filePath for sandboxed environments.
    public init(filePath: URL? = nil)

    @discardableResult
    public func add(score: Int, playerName: String) -> [StoredScore]

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

| File | Path (macOS) | Path (iOS) | Content |
|------|-------------|------------|---------|
| Scores | `~/.tetris/scores.json` | `~/Library/Application Support/Tetris/scores.json` | Top 10 scores with player name |
