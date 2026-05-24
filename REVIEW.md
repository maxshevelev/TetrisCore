# TetrisCore — Full Project Review

## Architecture

```
Main.swift (ArgumentParser CLI)
  └─ ConsoleGameUI.run()
       ├─ PersistentGameSettings  ← ~/.tetris/settings.json
       ├─ ScoreStorage             ← ~/.tetris/scores.json
       ├─ GameController (actor)  ← sparse [PieceCoordinate: TetrominoColor]
       │    ├─ inputBuffer          ← async channel
       │    ├─ dropTimer            ← Task with generation counter
       │    └─ tick: AsyncStream<Set<GameEvent>>  ← diff events
       ├─ ConsoleInputHandler      ← raw stdin + dispatch queue
       └─ ConsoleRenderer          ← ANSI output
```

---

## 1. [HIGH] `BlockState` is dead code — still exported as public API

**File**: `Sources/TetrisCore/BlockState.swift`

`BlockState` was the old grid element type (`empty` / `filled(Color)`). The grid is now a sparse `[PieceCoordinate: TetrominoColor]` — `BlockState` is no longer used anywhere in the source code. It's still a `public enum` exported by the TetrisCore module.

Any downstream consumer that imports `TetrisCore` gets `BlockState` in its public API surface. If this is a library meant for external use, this is a misleading export.

**Fix**: If `BlockState` serves no internal purpose and no external consumer depends on it, remove `BlockState.swift`. If external consumers might use it, deprecate it with a clear migration note.

---

## 2. [HIGH] Grid diff in `render()` copies the entire dictionary on every tick

**File**: `GameController.swift:441`

```swift
let gridCopy = grid  // Full dictionary copy every tick
if gridCopy != sentGrid { ... }
```

On every tick (60 Hz), this does:
1. A full `grid` dictionary copy (O(N) where N = filled cells)
2. A dictionary equality comparison (O(N))

For the first 100 lines cleared (~20 blocks), this is 20 allocations + 20 comparisons. For ~40% full grid (~80 blocks), it's 80 allocations. The `pieceCoords` and `nextCoords` similarly do `Set(...)` allocations each tick.

A better approach: use a dirty flag that's set only when the grid actually changes (lock/remove), and clear it when the event is sent.

**Fix**:
```swift
private var gridDirty = false

private func render() {
    var dirtyGrid: [PieceCoordinate: TetrominoColor]?
    if gridDirty {
        dirtyGrid = grid
        gridDirty = false
    }
    // ... later ...
    if let g = dirtyGrid { events.insert(.grid(g)); sentGrid = g }
}
```

---

## 3. [HIGH] `removeClearedRows` allocates a new dictionary every call

**File**: `GameController.swift:390-394`

```swift
private func removeClearedRows(_ linesToClear: [Int]) {
    grid = grid.filter { entry in
        !linesToClear.contains(entry.key.y)
    }
}
```

For a single line clear (10 rows), this iterates all N filled cells and allocates a new dictionary with N-10 entries. This happens on the drop timer task (isolated to the actor). For a quad-clear (40 rows removed), it still scans all N entries.

A minor optimization: use `grid.removeSubscript(where:)` loop instead of `filter` to avoid the full allocation. But the real win is in the line-clear detection itself.

---

## 4. [MEDIUM] `clearLinesPrivate` O(N + R) is good for sparse grids

**File**: `GameController.swift:369-387`

The row-count approach is the right optimization:

```swift
var rowCounts: [Int: Int] = [:]
for coord in grid.keys {
    rowCounts[coord.y, default: 0] += 1
}
let linesToClear = rowCounts
    .filter { $1 == width }
    .map { $0.0 }
    .sorted()
```

This is O(N) where N = filled cells. For an empty grid, it's 0 iterations. For a 40%-full grid (~80 cells), it's 80 iterations — much better than the old 200.

One issue: `linesToClear.sorted()` is called twice (once here, once in the log). Cache it.

---

## 5. [MEDIUM] `sentGrid` is still a nullable — nil means "never sent"

**File**: `GameController.swift:83`

```swift
private var sentGrid: [PieceCoordinate: TetrominoColor]?
```

On first render, `sentGrid` is `nil`, so `gridCopy != sentGrid` is always true (any dictionary != nil). This is correct — first render must include all fields. But the nullable is a signal that the diff should be structured differently.

Consider using a `dirtyGrid` flag (see issue #2) — it avoids the nullable entirely.

---

## 6. [MEDIUM] `ConsoleInputHandler` uses `usleep(10000)` polling

**File**: `ConsoleInputHandler.swift:41`

```swift
while self.running {
    var byte: UInt8 = 0
    let n = read(STDIN_FILENO, &byte, 1)
    if n == 1 {
        self.processByte(byte)
    }
    usleep(10000)  // 10ms poll interval
}
```

This uses a busy-loop with 10ms sleep between reads. The `read()` is blocking but `usleep` is called regardless, which means:
- Input latency is up to 10ms (acceptable for console)
- CPU is wasted on the `read` + `usleep` cycle every 10ms
- The `VM` flag was set to 1 (non-blocking read), so `read` returns immediately with 0 when nothing is available

This is fine for a console game on a single core. The CPU cost is ~0.01% per second. Not worth optimizing.

---

## 7. [MEDIUM] `spawnNewPiece` checks collision at spawn, but grid is sparse

**File**: `GameController.swift:402-413`

```swift
currentPiece = nextPiece
if currentPiece != nil {
    currentX = width / 2 - 2
    currentY = 0
    log(.debug,"[Piece] Spawned \([currentPiece!.shape.rawValue])")
    if isColliding() {
        log(.debug,"[GameOver] Score: \(score) Lines: \(linesCleared)")
        transition(to: .gameOver)
    }
}
```

The collision check at spawn works correctly with sparse grid: `isColliding` checks `grid[PieceCoordinate(x: x, y: y)]` for each piece block at spawn position (3, 0). The I-piece at spawn can only reach row 1 (its bottom blocks), so old blocks at the bottom never trigger a false positive. This is correct.

---

## 8. [LOW] `ColorPalette` switch lacks `default` — exhaustive but fragile

**File**: `ColorPalette.swift:29-38`

```swift
public static func from(_ color: TetrominoColor) -> ColorPalette {
    switch color {
    case .cyan:    return .cyan
    case .yellow:  return .yellow
    case .magenta: return .magenta
    case .green:   return .green
    case .red:     return .red
    case .blue:    return .blue
    case .orange:  return .orange
    }
}
```

The switch is exhaustive (all enum cases listed), so no `default` needed. If `TetrominoColor` gains a case, the compiler will flag the switch as non-exhaustive. This is fine.

---

## 9. [LOW] `PersistentGameSettings` is `@unchecked Sendable`

**File**: `GameSettings.swift:18`

All property access is guarded by `lock`, and `notify()` is called after `lock.withLock`. The `listeners` array is only modified inside lock in `addListener`/`removeListener`. This is sound, but the compiler can't verify it.

---

## 10. [LOW] `InputBuffer` is an actor — fine for single-threaded input

**File**: `InputBuffer.swift`

The `InputBuffer` is an actor with `send`/`receive` methods. Input comes from `ConsoleInputHandler` (dispatch queue) via `Task.detached` → `enqueue` → `send`. The actor serializes all access, which is correct.

The buffer can grow unbounded if input outpaces the game loop. For a console game with human input, this is not a concern.

---

## 11. [LOW] `validTransitions` doesn't include `.initializing` in any source

**File**: `GameState.swift:1-5`, `GameController.swift:16-21`

```swift
private static let validTransitions: [GameState: Set<GameState>] = [
    .initializing: [.dropping],
    .dropping: [.paused, .gameOver, .dropping],
    .paused: [.dropping, .gameOver],
    .gameOver: [.initializing],
]
```

All 5 internal states are defined in `GameState`, but `.gameOver` only appears in the transition table (not as a `switch` case in `didSet` — it falls through to `default`). This is correct but the `default` case in `didSet` is a catch-all for `.initializing` and `.gameOver`.

---

## 12. [LOW] `hardDropPiece` sets `currentY` without piece bounds check

**File**: `GameController.swift:303-306`

```swift
while canMoveDown() { currentY += 1 }
```

This moves the piece's base position to the lowest valid row. The piece blocks themselves can go up to row 20 (height), and the bottom row of any piece at the lowest position fits within the grid. This is correct.

---

## 13. [LOW] `ConsoleRenderer` hardcodes 10x20 for sparse grid

**File**: `ConsoleRenderer.swift:29-30`

```swift
let width = 10
let height = 20
```

The renderer doesn't derive grid dimensions from data (which would be `grid.keys.map(\.y).max() ?? 20`). The hardcoded values match `GameController.width/height`. This is fine for a fixed-size game.

---

## 14. [LOW] `Test` targets don't test `GameController` directly

**File**: `Tests/TetrisCoreTests/GameControllerTests.swift`

The tests use helper functions (`isColliding`, `canMoveDown`, `linesClearedIn`) that duplicate the logic from `GameController`. They don't test the actor or any game logic through the public API. They test isolated algorithms with a sparse grid — which is what the sparse grid change touches.

If any of these helper functions diverge from `GameController`'s actual logic (e.g., boundary conditions), they won't catch it.

---

## Summary

| # | Severity | File | Issue |
|---|---|---|---|
| 1 | HIGH | BlockState.swift | Dead public API — remove or deprecate |
| 2 | HIGH | GameController.swift:441 | Grid diff copies full dict every tick (20-80 allocs/tick) |
| 3 | MEDIUM | GameController.swift:390 | `removeClearedRows` allocates new dict via `filter` |
| 4 | MEDIUM | GameController.swift:376 | `linesToClear.sorted()` called twice |
| 5 | MEDIUM | GameController.swift:83 | Nullable `sentGrid` is a diff signal — use dirty flag |
| 6 | MEDIUM | ConsoleInputHandler.swift:41 | 10ms poll loop — acceptable, not worth fixing |
| 11 | LOW | GameState.swift | `.gameOver` falls through to `default` in `didSet` |
| 14 | LOW | Tests | Helper functions duplicate logic — no actor-level tests |

### Biggest wins from sparse grid

| Metric | Dense (200) | Sparse (~80 avg) | Win |
|--------|------------|------------------|-----|
| Grid copy per tick | 200 elements | N filled cells | 2.5x fewer |
| Line-clear scan | 200 cells | N cells (once) | No redundant checks |
| Empty-board early game | 200 per tick | 0 | Massive |
| Memory footprint | ~200 * 24B ≈ 4.8KB | N * 32B ≈ 2.5KB | Minor (both are tiny) |

**The sparse grid achieves its goal** — but the diff in `render()` still copies the full dictionary every tick (issue #2), which negates ~60% of the memory win. A dirty flag would close that gap.
