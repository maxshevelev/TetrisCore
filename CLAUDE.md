# Project Context

Console-based Tetris game built as a Swift Package with no external UI dependencies.

## Architecture & Stack

- **Swift Package** with 3 targets: `TetrisCore` (UI-agnostic game engine), `ConsoleUI` (terminal rendering/input), `tetris` (executable)
- **Platforms**: macOS 13+ and iOS 16+ (TetrisCore only; ConsoleUI is macOS-only reference impl)
- **SPM products**: `TetrisCore` and `ConsoleUI` available as explicit library products for Xcode integration
- **External dependency**: `swift-argument-parser` ≥1.7.1 for CLI argument parsing
- **Actor-based** `GameController` for concurrent, data-race-free game state
- **Actor-based** `InputBuffer` for input buffering between producer and consumer
- **Event-driven** input via `InputReceiver` protocol + `InputBuffer`
- **Async-first** lifecycle: `ConsoleInputHandler` exposes `exitContinuation` — `ConsoleGameUI` creates an `AsyncStream<Void>` after handler init completes, awaiting `exitStream.first(where:)` as the game-over signal
- **Sparse grid** — `[PieceCoordinate: TetrominoColor]` storing only filled cells. Rendering iterates the fixed 10×20 grid and looks up each coordinate. Line-clear scans only filled cells instead of all 200 rows. `BlockState` is deprecated — consumers use `TetrominoColor` directly.
- **Persistent score storage** in `~/.tetris/scores.json` (top 10, JSON-backed) — no date field. Deduplication is global (rejects exact score+name matches).
- **Persistent settings** in `~/.tetris/settings.json` — playerName, lockImmediatelyAfterHardDrop, isHardDropAnimated, isLineClearAnimated, initialLevel, ghostPieceEnabled. Backed by `GameSettings` protocol + `PersistentGameSettings`.
- **Optional debug logging** via `-d` flag with log level (debug, info, notice, error, fault), uses Apple `os.Logger` — all logs use `privacy: .public`
- **Optional player name** via `-u, --user` flag, defaults to Unix username
- **Color abstraction**: `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI) for ANSI mapping + ghost piece color (254)
- **Ghost piece**: enabled when `settings.isGhostPieceEnabled` — rendered with near-white fg/background (254 palette)
- **Tick-based update stream**: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>`. Each tick yields a set of `GameEvent` values — only changed fields are included. Absence from the set means unchanged. Consumers accumulate state by switching over events.
- **State machine**: `GameController` uses a validated transition graph — all state changes go through `transition(to:)`, timer lifecycle is managed exclusively in `state.didSet`. The internal `GameState` enum (5 cases) is mapped to a public `GameDisplayState` (3 cases: playing/paused/gameOver) for consumers.
- **SRS wall-kick**: Full SRS rotation tables with CW-kick lookup and automatic sign-flip for CCW transitions.
- **Line-clear animation**: Two-phase tick sequence (pre-clear + post-clear) when `isLineClearAnimated` is true.
- **Hard-drop animation**: Optional brief visual delay before piece locks.

## Key Files & Responsibilities

| File | Role |
|------|------|
| `Sources/tetris/Main.swift` | Entry point, ArgumentParser CLI, wires logger + UI |
| `Sources/TetrisCore/GameController.swift` | Actor: game loop, input handling, state machine (`transition(to:)`, `validTransitions`), scoring, ghost piece, `log` method |
| `Sources/TetrisCore/GameState.swift` | Internal state machine enum (5 internal states) — not exposed to consumers |
| `Sources/TetrisCore/GameDisplayState.swift` | Consumer-facing state enum (playing/paused/gameOver) — included in `GameEvent` |
| `Sources/TetrisCore/GameSettings.swift` | `GameSettings` protocol + `PersistentGameSettings` + `SettingsUpdateListener` |
| `Sources/TetrisCore/LogLevel.swift` | Log level enum — `allows` gates messages, used by `log(level, .)` |
| `Sources/TetrisCore/ScoreStorage.swift` | JSON persistence for top-10 scores, thread-safe via dispatch queue |
| `Sources/TetrisCore/Tetromino.swift` | Shape definitions, SRS rotation (`rotated(by:)`), block coordinates, wall-kick tables — immutable struct |
| `Sources/TetrisCore/GameEvent.swift` | Diff-style update event enum — each variant carries changed data; unused variants omitted from set |
| `Sources/TetrisCore/InputBuffer.swift` | Input producer/consumer actor — buffers or directly delivers ControlEvent |
| `Sources/ConsoleUI/ConsoleGameUI.swift` | Facade: creates `AsyncStream` for exit signal, accumulates tick events, orchestrates lifecycle |
| `Sources/ConsoleUI/ConsoleInputHandler.swift` | Raw stdin reader in raw mode — dispatches ControlEvent, exposes `exitContinuation` |
| `Sources/ConsoleUI/ConsoleRenderer.swift` | ANSI rendering, overlay system, game-over score table, ghost piece bg/fg |
| `Sources/ConsoleUI/TerminalAdapter.swift` | `TerminalOperations` protocol + `TerminalAdapter` — abstraction for termios/ioctl |

## Conventions & Constraints

- Game logic in `TetrisCore` is UI-agnostic; colors use `TetrominoColor`, rendering uses `ColorPalette`
- Actor isolation for `GameController` and `InputBuffer`; `@Sendable` closures for callbacks
- All log messages use `privacy: .public` — never hide logs from the user
- Overlay uses `OverlayLine` with `plain`/`bold` factories, optional `ColorPalette` color
- Grid rendering: virtual buffer → centered ANSI output
- Scoring: classical Tetris formula (40/100/300/1200 base, multiplied by level+1)
- Soft drop with lock delay (0.5s), piece movement resets timer
- `Tetromino` is an immutable `Sendable` struct — use `rotated(by:)`, never mutate `rotationIndex`
- `LogLevel` gates messages via `allows` — a level X permits messages at level X or higher
- `GameDisplayState`, `TetrominoColor`, `Tetromino`, `TetrominoShape`, `ColorPalette` are all `Sendable`. `GameState` is internal.
- State machine: all state changes go through `transition(to:)` backed by `validTransitions` table — invalid transitions are silently rejected with a debug log. Timer lifecycle is managed exclusively in `state.didSet`, never called directly.

⚠️ **DO NOT remove `SettingsUpdateListener` / `addListener` / `removeListener` from `GameSettings`** — it is a public API for package consumers, even though zero local consumers exist in this repo.

## Active Tasks & Status

- ✅ ArgumentParser integration — `-d` / `--user` flags working
- ✅ Score table with persistent JSON storage and game-over overlay — no date field, classical scoring
- ✅ Color abstraction: `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI)
- ✅ `Tetromino` immutable struct, `Sendable`
- ✅ `Tetromino.rotationIndex` is now `let` (immutable)
- ✅ `log(level, message)` — generic log method with `LogLevel` gating
- ✅ All log messages use `privacy: .public`
- ✅ Line clearing / line-clear animation unit tests added
- ✅ `awaitInput()` removed (dead code)
- ✅ Validated state machine: `validTransitions` table + `transition(to:)` — timer lifecycle through `didSet` only
- ✅ Consumer API: internal `GameState` mapped to public `GameDisplayState` (playing/paused/gameOver) — internal timer states hidden from consumers
- ✅ Tick-based update stream: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>` — only changed fields are yielded as events
- ⚠️ `ConsoleUI` target exists but NOT in `products` array — consumers can only add `TetrisCore` via SPM (see REVIEW.md §3.4)
- ✅ SRS wall-kick rotation implementation
- ✅ Ghost piece rendering
- ✅ `InputBuffer` actor for input buffering
- ✅ Game-over signal: `DispatchSemaphore` → native `AsyncStream<Void>` (async-first)
- ✅ Ghost piece bg+fg colors (254 palette)

## Remaining Issues (tracked in REVIEW.md)

⚠️ `hardDropPiece()` lacks `!isHardDropAnimating` guard at the control-event dispatch level — `moveLeft`/`moveRight`/`rotate` all guard, `hardDrop` does not (see REVIEW.md §2.4)
⚠️ `ScoreStorage.add()` rejects legitimate duplicate scores globally — same player + same score across two separate games is dropped (see REVIEW.md §2.5)
⚠️ `removeClearedRows(_:)` is O(n × m) with `linesToClear.filter` inside the loop — pre-compute a `Set<Int>` of cleared rows (see REVIEW.md §2.6)
⚠️ Two `canMoveDown` overloads: mutating version is fragile, use `canMoveDown(from:)` everywhere (see REVIEW.md §2.7)
⚠️ `wallKickOffsets` is module-internal — test target (and future consumers) must duplicate the entire SRS data (see REVIEW.md §3.3)
⚠️ Tests mirror internal helpers (`isColliding`, `canMoveDown`, `tryRotateWithKicks`) — zero `GameController` integration tests (see REVIEW.md §5)
⚠️ `shapes` array allocated fresh in `init()`, `resetGame()`, `spawnNextPiece()` — should be `private static let` (see REVIEW.md §6.1)
⚠️ `TetrominoShape.blocks` computed property allocates new `[[[Int]]]` on every access — see REVIEW.md §6.2
⚠️ Terminal size queried every render via `TIOCGWINSZ` ioctl — no SIGWINCH caching (see REVIEW.md §6.3)
⚠️ README control table conflates three behaviors per key (see REVIEW.md §4.4)
⚠️ README `VibeTetris` URL is stale (see REVIEW.md §4.5)
⚠️ README `BlockState` section is misleading — no migration table (see REVIEW.md §4.6)
⚠️ README `Tetromino` shows `rotationIndex` as `init` parameter, not `let` (see REVIEW.md §4.7)
⚠️ README `ControlEvent` source enum omits `.start` case (see REVIEW.md §4.8)

## Recent Changes

### 2026-05-29

- **Game-over signal modernization** — Replaced `DispatchSemaphore` + `withUnsafeContinuation` with native `AsyncStream<Void>` in `ConsoleInputHandler` + `ConsoleGameUI`
- **`Tetromino.rotationIndex` made `let`** — Immutable by default, prevents mutation misuse
- **`ConsoleUI` exposed as SPM product** — Now available as explicit dependency in `Package.swift`
- **Ghost piece rendering** — Shows ghost piece preview with near-white colors (254 palette)
- **`ghostPieceEnabled` setting** — Added to `GameSettings`, defaults to `true`
- **`ghostPieceBlocks` event** — Added to `GameEvent`, emitted when ghost piece is enabled
- **`gridSize(width: Int, height: Int)` event** — Added to `GameEvent`, emitted on initial tick
- **`hardDropDuration` in `pieceBlocks`** — Optional field to track hard-drop timing
- **SRS wall-kick implementation** — Full SRS wall-kick tables with proper CW/CCW flip logic
- **`CellType` abstraction** — Added `CellType` enum for clearer block state representation
- **`InputReceiver` protocol** — Unified input handling via `enqueue(_:)` method
- **`isGhostPieceEnabled` in `GameSettings` protocol**
- **`gameOverOverlay` rendering** — Dedicated overlay rendering for game-over screen
- **REVIEW.md** — Full project review with 14 findings (5 bugs, 4 docs, 5 minor) across 3 sections: architecture, correctness, and test coverage
- **`isGhostPieceEnabled` in `GameSettings` protocol**
- **`gameOverOverlay` rendering** — Dedicated overlay rendering for game-over screen
