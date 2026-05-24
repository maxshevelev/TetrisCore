# Project Context

Console-based Tetris game built as a Swift Package with no external UI dependencies.

## Architecture & Stack

- **Swift Package** with 3 targets: `TetrisCore` (UI-agnostic game engine), `ConsoleUI` (terminal rendering/input), `tetris` (executable)
- **Platforms**: macOS 13+ and iOS 16+ (TetrisCore only; ConsoleUI is macOS-only reference impl)
- **SPM products**: `TetrisCore` and `ConsoleUI` available as explicit library products for Xcode integration
- **External dependency**: `swift-argument-parser` ≥1.4.0 for CLI argument parsing
- **Actor-based** `GameController` for concurrent, data-race-free game state
- **Event-driven** input via `InputReceiver` protocol + `InputBuffer`
- **Sparse grid** — `[PieceCoordinate: TetrominoColor]` storing only filled cells. Rendering iterates the fixed 10×20 grid and looks up each coordinate. Line-clear scans only filled cells instead of all 200 rows. `BlockState` is internal-only and deprecated for external consumers.
- **Persistent score storage** in `~/.tetris/scores.json` (top 10, JSON-backed) — no date field
- **Optional debug logging** via `-d` flag with log level (debug, info, notice, error, fault), uses Apple `os.Logger` — all logs use `privacy: .public`
- **Optional player name** via `-u, --user` flag, persisted in `~/.tetris/settings.json`, defaults to Unix username
- **Color abstraction**: `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI) for ANSI mapping
- **Tick-based update stream**: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>`. Each tick yields a set of `GameEvent` values — only changed fields are included. Absence from the set means unchanged. Consumers accumulate state by switching over events.
- **State machine**: `GameController` uses a validated transition graph — all state changes go through `transition(to:)`, timer lifecycle is managed exclusively in `state.didSet`. The internal `GameState` enum (5 cases) is mapped to a public `GameDisplayState` (3 cases: playing/paused/gameOver) for consumers.

## Key Files & Responsibilities

| File | Role |
|------|------|
| `Sources/tetris/Main.swift` | Entry point, ArgumentParser CLI, wires logger + UI |
| `Sources/TetrisCore/GameController.swift` | Actor: game loop, input handling, state machine (`transition(to:)`, `validTransitions`), scoring, `log` method |
| `Sources/TetrisCore/GameState.swift` | Internal state machine enum (5 internal states) — not exposed to consumers |
| `Sources/TetrisCore/GameDisplayState.swift` | Consumer-facing state enum (playing/paused/gameOver) — included in `GameEvent` |
| `Sources/TetrisCore/LogLevel.swift` | Log level enum — `allows` gates messages, used by `log(level, .)` |
| `Sources/ConsoleUI/ColorPalette.swift` | ANSI color palette, maps `TetrominoColor` → `ColorPalette` |
| `Sources/TetrisCore/ScoreStorage.swift` | JSON persistence for top-10 scores, thread-safe |
| `Sources/TetrisCore/GameEvent.swift` | Diff-style update event enum — each variant carries changed data; unused variants omitted from set |
| `Sources/ConsoleUI/ConsoleGameUI.swift` | Facade: adapter pattern, lifecycle management |
| `Sources/ConsoleUI/TerminalAdapter.swift` | Terminal operations abstraction |
| `Sources/TetrisCore/Tetromino.swift` | Shape definitions, rotation (`rotated(by:)`), block coordinates — immutable struct |

## Conventions & Constraints

- Game logic in `TetrisCore` is UI-agnostic; colors use `TetrominoColor`, rendering uses `ColorPalette`
- Actor isolation for `GameController`; `@Sendable` closures for callbacks
- All log messages use `privacy: .public` — never hide logs from the user
- Overlay uses `OverlayLine` with `plain`/`bold` factories, optional `ColorPalette` color
- Grid rendering: virtual buffer → centered ANSI output
- Scoring: classical Tetris formula (40/100/300/1200 base, multiplied by level+1)
- Soft drop with lock delay (0.5s), piece movement resets timer
- `Tetromino` is an immutable `Sendable` struct — use `rotated(by:)`, never mutate in place
- `LogLevel` gates messages via `allows` — a level X permits messages at level X or higher
- `GameDisplayState`, `TetrominoColor`, `Tetromino`, `TetrominoShape`, `ColorPalette` are all `Sendable`. `GameState` is internal.
- State machine: all state changes go through `transition(to:)` backed by `validTransitions` table — invalid transitions are silently rejected with a debug log. Timer lifecycle is managed exclusively in `state.didSet`, never called directly.

⚠️ **DO NOT remove `SettingsUpdateListener` / `addListener` / `removeListener` from `GameSettings`** — it is a public API for package consumers, even though zero local consumers exist in this repo.

## Active Tasks & Status

- ✅ ArgumentParser integration — `-d` / `--user` flags working
- ✅ Score table with persistent JSON storage and game-over overlay — no date field, classical scoring
- ✅ Color abstraction: `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI)
- ✅ `Tetromino` immutable struct, `Sendable`
- ✅ `log(level, message)` — generic log method with `LogLevel` gating
- ✅ All log messages use `privacy: .public`
- ✅ Line clearing unit tests added
- ✅ `awaitInput()` removed (dead code)
- ✅ Validated state machine: `validTransitions` table + `transition(to:)` — timer lifecycle through `didSet` only
- ✅ Consumer API: internal `GameState` mapped to public `GameDisplayState` (playing/paused/gameOver) — internal timer states hidden from consumers
- ✅ Tick-based update stream: `GameController` exposes `nonisolated public let tick: AsyncStream<Set<GameEvent>>` — only changed fields are yielded as events; absence from set means unchanged
