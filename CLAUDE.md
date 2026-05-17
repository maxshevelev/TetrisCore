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
  - **GameController.swift** - Event-driven actor managing game state, timing, and input handling

- **Sources/ConsoleUI/** - Console-based UI implementation
  - **Terminal.swift** - Terminal control utilities (clear screen, cursor visibility, ANSI colors, terminal size detection)
  - **TerminalAdapter.swift** - Adapter pattern for terminal operations (extracted for testability)
  - **ConsoleRenderer.swift** - Renders game state to ANSI escape sequences for terminal display
  - **ConsoleInputHandler.swift** - Non-blocking stdin reader using dispatch queue and raw terminal mode
  - **ConsoleGameUI.swift** - Facade integrating controller, renderer, and input handler

## Key Design Decisions

1. **No external dependencies** - Uses Darwin for terminal I/O (tcgetattr/tcsetattr, ioctl)
2. **Serial input queue** - Input reading runs on a dedicated serial queue; input is sent to actor via `enqueue()`
3. **Event-driven architecture** - `GameController` is an actor that receives events via `InputReceiver` protocol
4. **Ansi escape sequences** - Terminal rendering uses escape codes for cursor positioning and colors
5. **Grid-based rendering** - Board renders to virtual coordinates then centers based on actual terminal size
6. **Soft drop with lock delay** - Pieces automatically drop; after user movement, pieces lock after 0.5s of no movement
7. **Testable game logic** - Game logic extracted into public methods (`moveLeft`, `moveRight`, `rotatePiece`, `hardDropPiece`, `isColliding`) and private helpers with `Private` suffix for unit testing
8. **Terminal state restoration** - Explicit `cleanup()` call in `ConsoleGameUI.run()` ensures terminal mode is restored on exit
9. **Line clearing order** - Lines cleared in ascending order to avoid index shifting issues when removing multiple adjacent lines
