# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build and Run

```bash
swift build      # Build the project
swift run tetris # Run the game
```

## Architecture

The tetris game is structured as a Swift Package with a single `tetris` target, following a clean separation of concerns:

- **Sources/Model/** - UI-agnostic game logic
  - **BlockState.swift** - Abstract block states (`empty`, `filled(TetrominoColor)`) for UI-independent grid representation
  - **TetrominoColor.swift** - Color enum for tetromino pieces with `ansiCode` property for terminal rendering
  - **Tetromino.swift** - Tetromino shape definitions (I, O, T, S, Z, J, L) with rotation states and block coordinates
  - **TetrisGame.swift** - Core game logic: grid management, collision detection, piece spawning, line clearing, scoring

- **Sources/UI/** - UI-specific implementations
  - **Main.swift** - Entry point with game loop, input handling, and rendering coordination
  - **Terminal.swift** - Terminal control utilities (clear screen, cursor visibility, ANSI colors, terminal size detection)
  - **InputHandler.swift** - Non-blocking stdin reader using dispatch queue and raw terminal mode
  - **GameRenderer.swift** - Renders game state to ANSI escape sequences for terminal display

## Key Design Decisions

1. **No external dependencies** - Uses Darwin for terminal I/O (tcgetattr/tcsetattr, ioctl)
2. **Serial input queue** - Input reading runs on a dedicated serial queue; `lastChar` is accessed via queue synchronization
3. **Ansi escape sequences** - Terminal rendering uses escape codes for cursor positioning and colors
4. **Grid-based rendering** - Board renders to virtual coordinates then centers based on actual terminal size
5. **Soft drop with lock delay** - Pieces automatically drop; after user movement, pieces lock after 0.5s of no movement
6. **UI-agnostic game logic** - `TetrisGame` contains pure game state (grid, pieces, score) and logic (move, rotate, collide, lock, clear). The `GameRenderer` receives game state as parameters and returns a render string. This enables attaching different UI layers (console, graphics, web) to the same game logic.
