# TetrisCore — Full Project Review

**Date**: 2026-05-29
**Branch**: main
**Files**: 13 TetrisCore sources, 6 ConsoleUI sources, 1 test file, Package.swift
**Scope**: All source files, Package.swift, README.md, CLAUDE.md

---

## 1. Architecture

### ✅ Strengths

| Aspect | Assessment |
|--------|---------|
| **Three-layer split** | TetrisCore / ConsoleUI / tetris — clean boundaries, no leakage |
| **Actor-based concurrency** | `GameController` + `InputBuffer` are actors — data races impossible across the boundary |
| **Diff-style tick stream** | `Set<GameEvent>` per tick, only yielded events change — minimal IPC overhead |
| **Validated state machine** | `validTransitions` table + `transition(to:)` — invalid transitions silently rejected with debug log |
| **Timer lifecycle** | `state.didSet` manages timers exclusively — consistent lifecycle management |
| **Sparse grid** | `[PieceCoordinate: TetrominoColor]` — iteration cost proportional to filled cells |
| **SRS wall-kick** | Full CW/CCW table with automatic sign-flip — correct |
| **Color abstraction** | `TetrominoColor` (TetrisCore) → `ColorPalette` (ConsoleUI) — renderer-agnostic |
| **Protocol-based dependencies** | `InputReceiver`, `GameRenderer`, `TerminalOperations`, `GameSettings` — swappable implementations |

### 🔍 Architectural Concerns

| Issue | Severity | Detail |
|-------|---------|--------|
| **`ConsoleGameUI` is `@unchecked Sendable`** | Medium | `currentDisplayState` is written from the input queue thread (line 55 of ConsoleGameUI) and read from `processByte` (line 80 of ConsoleInputHandler). No synchronization. Race window is narrow but technically UB under Swift 6. |
| **`ConsoleInputHandler` is `@unchecked Sendable`** | Low | Accessed only from `inputQueue` except `running` and `exitContinuation` which are set on the caller thread. Works in practice but violates Swift 6 concurrency rules. |
| **`spawnNewPiece` / `spawnNextPiece` naming** | Low | Private `spawnNewPiece()` (lines 437–449) calls private `spawnNextPiece()` (line 448) on `self`. Three public consumers (`restart`, `clearLinesPrivate`, `init`) call `spawnNewPiece` which calls `spawnNextPiece`. Easy to confuse. |

---

## 2. Bugs & Correctness

### ⚠️ 2.1 `ScoreStorage.add()` deduplicates globally (ScoreStorage, line 35)

```swift
guard !loadScores().contains(where: { $0.score == score && $0.playerName == playerName }) else { ... }
```

Scores are deduplicated across all games. A player who achieves the same score in two separate sessions will have the second score rejected.

**Severity**: Medium.

### ⚠️ 2.2 `removeClearedRows(_:)` is O(n × m) (GameController, line 423)

```swift
let shift = linesToClear.filter { $0 > entry.key.y }.count
```

The filter iterates `linesToClear` for every grid entry. With ~200 cells and 4 cleared rows = 800 iterations. Pre-compute a `Set<Int>` for O(1) membership.

**Severity**: Low. Unmeasurable at 200 cells. But unnecessary.

### ⚠️ 2.3 `canMoveDown(from:)` returns `false` for `y >= height` (GameController, line 375)

When the piece is entirely below the grid (`y >= height`), `canMoveDown` returns `false` because `py >= height` is true. But the piece is already off the board — it shouldn't be blocked.

**Severity**: Low. `ghostPieceCoords` iterates upward, so the piece is always on or above the board. No real-world impact.

### ⚠️ 2.4 `shapes` array allocated on every call (GameController, lines 115, 200, 430)

```swift
let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

Allocated fresh in `init()`, `resetGame()`, and `spawnNextPiece()`. Should be `private static let allShapes`.

**Severity**: Low. Negligible per-call cost; wasted allocation pattern.

###  2.5 Ghost piece not emitted after hard drop animation (GameController)

When `isHardDropAnimated = true` and `lockImmediatelyAfterHardDrop = false`, the ghost piece coordinates and the hard-drop hint emit on different ticks.

**Severity**: Low. The ConsoleUI renderer accumulates state correctly.

---

## 3. Concurrency & Threading

### ⚠️ 3.1 `ConsoleGameUI` and `ConsoleInputHandler` are `@unchecked Sendable`

Both classes are marked `@unchecked Sendable` with no actual synchronization for cross-thread reads. `ConsoleGameUI.currentDisplayState` is written from the tick task and read from `ConsoleInputHandler.processByte` on the `inputQueue`. These are the *same* queue, so the read is on the same thread as the write — actually fine.

The real concern is `ConsoleGameUI` itself: `tasks` array is accessed from `run()` and potentially from other callers. No lock protects it.

**Severity**: Low-Medium. Works in practice because the only cross-thread access is within the same `inputQueue`. But `@unchecked Sendable` is a lie under Swift 6.

**Fix**: Use a dedicated serial queue for all access to `currentDisplayState`, or make it `actor`-backed.

### ⚠️ 3.2 `PersistentGameSettings` is `@unchecked Sendable` (GameSettings, line 20)

Protected by `NSLock` — safe. `notify()` deliberately releases the lock before iterating listeners (deadlock avoidance) — well-documented and correct.

**Verdict**: OK as-is.

### ⚠️ 3.3 `tickContinuation` is force-unwrapped (GameController, line 110)

```swift
var tkc: AsyncStream<Set<GameEvent>>.Continuation!
let tks = AsyncStream<Set<GameEvent>> { tkc = $0 }
self.tickContinuation = tkc
```

If `AsyncStream` init calls the closure synchronously, `tkc` is set before the assignment. In practice `AsyncStream` always calls the closure before returning, so this is safe. But the `!` is unnecessary — use a regular variable with a safe default.

**Severity**: Low. Not a realistic risk with `AsyncStream` implementation.

---

## 4. Test Coverage

### ⚠️ 4.1 Tests verify mirrored helpers, not `GameController`

All 28 tests exercise free functions (`isColliding`, `canMoveDown`, `tryRotateWithKicks`, `cwKickTable`) that duplicate internal logic from `GameController` and `Tetromino`. Zero tests instantiate `GameController`, enqueue events, or assert tick output. A divergence between test helpers and actor internals goes undetected.

**Missing coverage**:
- State machine transitions (pause → resume → stop → game over → restart)
- Scoring formula (40/100/300/1200 × level+1)
- Level progression and drop interval calculation
- Ghost piece coordinate emission
- `GameSettings` persistence and listener notification
- `ScoreStorage` concurrent access safety
- Hard-drop animation and lock-delay paths
- Line-clear animation two-phase tick sequence
- `spawnNewPiece()` / `spawnNextPiece()` interaction

**Severity**: Medium. Tests pass but don't protect against regressions in the actual engine.

### 4.2 Wall-kick tests duplicate SRS data

The test file re-implements `cwKickTable` (lines 295–321) and `rotationStateCount` (lines 324–330) — duplicated SRS data from `Tetromino.swift`. If the kick tables change, these tests silently test the wrong offsets.

### 4.3 `clearLines_in` helper is fragile

The test helper `linesClearedIn` (line 223) counts rows that are full, but the actual `clearLinesPrivate` logic iterates grid keys and counts per-row — identical approach but untested in the context of the actual `GameController` actor.

---

## 5. API & Documentation

### 5.1 README controls table conflates three behaviors per key

The table at README lines 60–67 maps each key to one action per state. Space maps to hard drop / resume / new-game across states. This conflates three distinct `ControlEvent` values behind one key.

**Severity**: Low. Reader confusion. The table is clear enough if read carefully.

### 5.2 README API documentation is consistent with actual code

- `GameController` init parameters: README line 128–133 shows `Logger()` default, but the actual default is `Logger()` (subsystem: "com.maxik.tetris") — correct.
- `ControlEvent` enum: README line 224 lists all cases including `.start` — correct.
- `GameDisplayState` doc: README line 294–298 matches actual enum — correct.

**Verdict**: README is current. No issues found.

### 5.3 README scoring table alignment (README line 395)

```
| Lines Cleared | Base Score |
|---------------|-----------|
```

The table header separators are misaligned. Minor formatting issue.

**Severity**: Cosmetic.

---

## 6. Prioritized Findings

| # | Status | Issue | Severity | Effort |
|---|--------|---|----|---|
| 1 | ⚠️ | Tests don't exercise `GameController` at all — no integration tests | Medium | 30 min |
| 2 | ⚠️ | `ConsoleGameUI` / `ConsoleInputHandler` `@unchecked Sendable` | Low-Medium | 10 min |
| 3 | ⚠️ | Drop timer dead after hard drop with animation (`lockImmediatelyAfterHardDrop = false`) | Medium | 2 min |
| 4 | ⚠️ | ScoreStorage dedup is global, not per-game | Medium | 5 min |
| 5 | ⚠️ | `removeClearedRows` O(n × m) — pre-compute `Set<Int>` | Low | 2 min |
| 6 | ⚠️ | `canMoveDown` returns false for off-board pieces | Low | 1 min |
| 7 | ⚠️ | `shapes` array allocated on every call | Low | 2 min |
| 8 | ⚠️ | README scoring table alignment | Cosmetic | 1 min |

---

## Conclusion

The project has a **strong architectural foundation** — clean layer separation, validated state machine, actor-based concurrency, sparse grid, and correct SRS wall-kick. The public API (tick stream, `GameDisplayState`, `GameSettings`) is well-designed for consumer embedding.

**Previously fixed (no longer concerns)**:

1. ✅ Double `nextPiece` assignment — removed dead code
2. ✅ `hardDropPiece()` animation guard added
3. ✅ Drop timer restart after hard drop animation
4. ✅ `TetrominoShape.blocks` static constants — zero per-call allocation
5. ✅ `GameState.description` visibility reduced to internal
6. ✅ `.start` for game-over restart documented
7. ✅ Terminal size per-frame documented as intentional (dynamic resize)
8. ✅ ScoreStorage iOS path safety with `#elseif os(iOS)`
9. ✅ ConsoleUI documented as macOS-only

**Remaining (unresolved)**:

See items 1–8 in Prioritized Findings above.
