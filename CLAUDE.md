# Project Context

Console-based Tetris game built as a Swift Package with no external UI dependencies.

## Architecture & Stack

- **Swift Package** with 3 targets: `TetrisCore` (UI-agnostic game engine), `ConsoleUI` (terminal rendering/input), `tetris` (executable)
- **Platforms**: macOS 13+ and iOS 16+ (TetrisCore only; ConsoleUI is macOS-only reference impl)
- **SPM products**: `TetrisCore` and `ConsoleUI` available as explicit library products for Xcode integration
- **External dependency**: `swift-argument-parser` ≥1.4.0 for CLI argument parsing
- **Actor-based** `GameController` for concurrent, data-race-free game state
- **Event-driven** input via `InputReceiver` protocol + `InputBuffer`
- **Virtual grid rendering** with ANSI escape sequences, centered on terminal
- **Persistent score storage** in `~/.tetris/scores.json` (top 10, JSON-backed) — no date field
- **Optional debug logging** via `-d` flag with log level (debug, info, notice, error, fault), uses Apple `os.Logger` — all logs use `privacy: .public`
- **Optional player name** via `-u, --user` flag, persisted in `~/.tetris/settings.json`, defaults to Unix username
- **Color abstraction**: `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI) for ANSI mapping
- **State machine**: `GameController` uses a validated transition graph — all state changes go through `transition(to:)`, timer lifecycle is managed exclusively in `state.didSet`

## Key Files & Responsibilities

| File | Role |
|------|------|
| `Sources/tetris/Main.swift` | Entry point, ArgumentParser CLI, wires logger + UI |
| `Sources/TetrisCore/GameController.swift` | Actor: game loop, input handling, state machine (`transition(to:)`, `validTransitions`), scoring, `log` method |
| `Sources/TetrisCore/GameState.swift` | Game state enum with validated transition graph — all state changes go through `transition(to:)` in GameController |
| `Sources/TetrisCore/LogLevel.swift` | Log level enum — `allows` gates messages, used by `log(level, .)` |
| `Sources/ConsoleUI/ColorPalette.swift` | ANSI color palette, maps `TetrominoColor` → `ColorPalette` |
| `Sources/TetrisCore/ScoreStorage.swift` | JSON persistence for top-10 scores, thread-safe |
| `Sources/TetrisCore/GameSessionState.swift` | Immutable snapshot passed to renderer |
| `Sources/ConsoleUI/ConsoleRenderer.swift` | Virtual grid → ANSI, overlay system with `OverlayLine` |
| `Sources/ConsoleUI/ConsoleGameUI.swift` | Facade: adapter pattern, lifecycle management |
| `Sources/ConsoleUI/TerminalAdapter.swift` | Terminal operations abstraction |
| `Sources/TetrisCore/Tetromino.swift` | Shape definitions, rotation (`rotated(by:)`), block coordinates — immutable struct |
| `Sources/TetrisCore/BlockState.swift` | `empty` / `filled(TetrominoColor)` enum |

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
- `GameState`, `TetrominoColor`, `Tetromino`, `TetrominoShape`, `ColorPalette` are all `Sendable`
- State machine: all state changes go through `transition(to:)` backed by `validTransitions` table — invalid transitions are silently rejected with a debug log. Timer lifecycle is managed exclusively in `state.didSet`, never called directly.

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
