# Project Context

Console-based Tetris game built as a Swift Package with no external UI dependencies.

## Architecture & Stack

- **Swift Package** with 3 targets: `Model` (game logic), `ConsoleUI` (terminal rendering/input), `tetris` (executable)
- **External dependency**: `swift-argument-parser` ≥1.4.0 for CLI argument parsing
- **Actor-based** `GameController` for concurrent, data-race-free game state
- **Event-driven** input via `InputReceiver` protocol + `InputBuffer`
- **Virtual grid rendering** with ANSI escape sequences, centered on terminal
- **Persistent score storage** in `~/.tetris/scores.json` (top 10, JSON-backed)
- **Optional debug logging** via `-d <file>` flag, timestamps each entry

## Key Files & Responsibilities

| File | Role |
|------|------|
| `Sources/tetris/Main.swift` | Entry point, ArgumentParser CLI, wires logger + UI |
| `Sources/Model/GameController.swift` | Actor: game loop, input handling, state machine, scoring |
| `Sources/Model/GameLogger.swift` | Sendable closure wrapper for debug logging |
| `Sources/Model/ScoreStorage.swift` | JSON persistence for top-10 scores, thread-safe |
| `Sources/Model/GameSessionState.swift` | Immutable snapshot passed to renderer |
| `Sources/ConsoleUI/ConsoleRenderer.swift` | Virtual grid → ANSI, overlay system with `OverlayLine` |
| `Sources/ConsoleUI/ConsoleGameUI.swift` | Facade: adapter pattern, lifecycle management |
| `Sources/ConsoleUI/TerminalAdapter.swift` | Terminal operations abstraction |
| `Sources/Model/Tetromino.swift` | Shape definitions, rotation, block coordinates |
| `Sources/Model/BlockState.swift` | `empty` / `filled(TetrominoColor)` enum |

## Conventions & Constraints

- No external UI dependencies — Darwin-only terminal I/O
- Game logic in `Model` is UI-agnostic
- Actor isolation for `GameController`; `@Sendable` closures for callbacks
- Overlay uses `OverlayLine` with `plain`/`bold` factories, optional color
- Grid rendering: virtual buffer → centered ANSI output
- Soft drop with lock delay (0.5s), piece movement resets timer
- Scores deduplicated on save; top 10 kept by score descending
- Log file created on demand if `-d <path>` specified

## Active Tasks & Status

- ✅ ArgumentParser integration — `-d` / `--debug` flag working
- ✅ Score table with persistent JSON storage and game-over overlay
- ✅ Debug logging across GameController lifecycle events
- ✅ OverlayLine refactored with `bold` factory and optional color
