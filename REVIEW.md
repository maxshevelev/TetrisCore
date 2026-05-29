# TetrisCore — Full Project Review

**Date**: 2026-05-28
**Branch**: main
**Files**: 20 sources, 1 test file, Package.swift

---

## 1. Architecture

The three-layer split (TetrisCore / ConsoleUI / tetris) is clean and well-maintained. The actor-based `GameController` with diff-style `AsyncStream<Set<GameEvent>>` is a sound event-driven architecture — consumers accumulate state by switching over event sets, which minimizes per-tick data transfer.

The validated `validTransitions` table centralizes state machine logic. Timer lifecycle in `state.didSet` ensures consistent start/stop behavior regardless of which code path triggers a transition. The internal `GameState` (5 cases) is correctly mapped to a public `GameDisplayState` (3 cases), hiding timer internals from consumers.

**Assessment**: Solid. Layer boundaries are strict, public API surface is minimal, and the sparse grid (`[PieceCoordinate: TetrominoColor]`) is an efficient representation.

---

## 2. Bugs & Correctness

### 2.1 `hardDropPiece` can run during active hard-drop animation (GameController:318-319)

`hardDropPiece` only guards `isPlaying`. The movement methods (`moveLeft`, `moveRight`, `rotatePiece`) additionally guard `!isHardDropAnimating`. If two hard-drop events are queued rapidly, the second enters while `isHardDropAnimating == true`. The animation branch is skipped (because the guard falls through), and we hit the non-animated path with `pieceBlockedOnLastTick = true` — but the animation timer is still running with a stale `dropTimerGeneration`. The animation timer fires later, checks `dropTimerGeneration`, and returns early — so in practice the generation guard prevents corruption. However, the `pendingHardDropDuration` could be set by the second call and consumed in the same render, sending a spurious hard-drop hint for a non-animated position.

**Severity**: Low-Medium. The generation guard limits real damage, but the behavior is undefined and input-dependent.

**Fix**: Add `!isHardDropAnimating` guard at the dispatch level (input listener switch, line 253) to reject hard-drop events while animating.

### 2.2 `Tetromino.rotationIndex` is `var` despite documented immutability (Tetromino:66)

CLAUDE.md states "`Tetromino` is an immutable `Sendable` struct — use `rotated(by:)`, never mutate in place." Yet `rotationIndex` is `var`, allowing `piece.rotationIndex += 1` from any caller. The `blocks` computed property handles negative indices gracefully via modular arithmetic, so out-of-bounds rotation doesn't crash — but it undermines the design intent.

**Severity**: Medium. Encourages misuse patterns.

**Fix**: Change to `let rotationIndex: Int`.

### 2.3 `ScoreStorage.add()` rejects legitimate duplicate scores (ScoreStorage:35)

```swift
guard !loadScores().contains(where: { $0.score == score && $0.playerName == playerName })
```

If Alice scores exactly 1200 twice in separate games, the second is silently dropped. The intent is to prevent double-save from a single game-over, but the check is global and permanent.

**Severity**: Low. Rare in practice (exact score match is uncommon) but semantically wrong.

**Fix**: Remove the duplicate check entirely, or add a `gameId`/timestamp to scope deduplication.

### 2.4 `removeClearedRows` is O(n × m) per cell (GameController:422-429)

For each of ~200 grid entries, `linesToClear.filter { $0 > entry.key.y }` scans the cleared-rows array. With 4 cleared rows and a full board, ~800 filter calls. The array is already sorted — a `Set<Int>` lookup for the "below this row" count would be O(1) per cell.

**Severity**: Low. Not a measurable hotspot at 200 cells, but incorrect complexity class.

**Fix**: Pre-compute a `Set<Int>` of cleared rows and use `clearedRows.filter { $0 < entry.key.y }.count` or maintain a running index.

### 2.5 Mutating `canMoveDown()` vs pure `canMoveDown(from:)` (GameController:357 vs 374)

Two overloads serve the same semantic purpose. The mutating version (line 357) increments/decrements `currentY` as side-effect, which is fragile. The pure version (line 374) takes `y` as parameter. The mutating version is only called once (drop timer, line 156).

**Severity**: Low. Code clarity issue.

**Fix**: Remove the mutating `canMoveDown()` and call `canMoveDown(from: currentY)` at the single call site.

---

## 3. Concurrency & Async

### 3.1 `ConsoleGameUI` bridges async/await with DispatchSemaphore (ConsoleGameUI:32, 68-73)

The game-over signal path uses `DispatchSemaphore.wait()` on a global dispatch queue, wrapped in `withUnsafeContinuation`. This blocks a libdispatch thread and crosses concurrency domains. The `tasks.forEach { $0.cancel() }` cleanup after resume is fire-and-forget — cancellation results aren't awaited.

**Severity**: Medium. Works in practice but defeats structured concurrency guarantees.

**Fix**: Replace with an `AsyncStream<Void>` that the input handler finishes on exit. Await cancellation of tasks explicitly.

### 3.2 `wallKickOffsets` is internal-only (Tetromino:119)

The SRS wall-kick function is file-private to `Tetromino.swift`'s module but not `public`. The test target (`TetrisCoreTests`) cannot import it and instead duplicates the entire kick table (lines 295-321). Any future target depending on TetrisCore faces the same duplication.

**Severity**: Low-Medium. Test duplication is a maintenance burden.

**Fix**: Make `public` or provide a `Tetromino.tryRotate(with:grid at:)` encapsulation method.

---

## 4. API & Packaging

### 4.1 `ConsoleUI` missing from Package.swift products

CLAUDE.md lists both `TetrisCore` and `ConsoleUI` as SPM products. Only `TetrisCore` appears in the `products` array (Package.swift:13). External consumers cannot depend on `ConsoleUI`.

**Severity**: Low. No known external consumers.

**Fix**: Add `.library(name: "ConsoleUI", targets: ["ConsoleUI"])`.

### 4.2 README documents `BlockState` as both "Removed" and shows full API (README:289-301)

The section header says "Removed: ...deleted" but then renders the full enum, properties, and API signature. Contradictory — either it's gone or it isn't.

**Severity**: Low. Documentation confusion.

**Fix**: Remove the API block or replace with a migration note.

### 4.3 README control table conflates three behaviors per key (README:58-65)

"Space — Hard Drop / Start New Game / Resume" maps three distinct `ControlEvent` values to one bullet. Similarly "q — Stop Playing / Exit from Game Over" conflates `.stop` and `onExit`.

**Severity**: Low. Reader confusion.

**Fix**: Split per context: "SPACE (playing) — hard drop", "SPACE (game over) — new game", etc.

---

## 5. Test Coverage

### 5.1 Tests verify local helpers, not `GameController` (GameControllerTests:1-439)

All 20+ tests exercise free functions (`isColliding`, `canMoveDown`, `tryRotateWithKicks`) that duplicate internal logic. Zero tests instantiate `GameController`, enqueue events, or assert tick output. A divergence between test helpers and actor internals goes undetected.

**Missing coverage**:
- State machine transitions (pause → resume → stop → game over → restart)
- Scoring formula (40/100/300/1200 × level+1)
- Level progression and drop interval calculation
- Ghost piece coordinate emission
- `GameSettings` persistence and listener notification
- `ScoreStorage` concurrent access safety
- Hard-drop animation and lock-delay paths
- Line-clear animation two-phase tick sequence

**Severity**: Medium. Tests pass but don't protect against regressions in the actual engine.

### 5.2 Wall-kick tests mirror internal data (GameControllerTests:293-321)

The test file re-implements `cwKickTable` and `rotationStateCount` — 28 lines of duplicated SRS data. If the kick tables in `Tetromino.swift` change, these tests silently test the wrong offsets.

---

## 6. Minor Issues

### 6.1 `shapes` array allocated on every call (GameController:115, 201, 432)

```swift
let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

Allocated fresh in `init()`, `resetGame()`, and `spawnNextPiece()`. Should be `private static let allShapes`.

### 6.2 `usleep(10000)` deprecated on macOS 13+ (ConsoleInputHandler:41)

10ms poll in the input read loop. `usleep` is available but marked deprecated. Consider `Thread.sleep(for: .milliseconds(10))` or `select()` with timeout on stdin.

### 6.3 Terminal size queried every render (ConsoleRenderer:18)

`ioctl(TIOCGWINSZ)` on every tick. Terminal dimensions are stable during gameplay. Cache and refresh on SIGWINCH.

### 6.4 `TetrominoShape.blocks` allocates new arrays per access (Tetromino:20-61)

Computed property returns fresh `[[[Int]]]` on every call. The shape data is compile-time constant. Pre-compute as `static let`.

---

## 7. Prioritized Findings

| # | Issue | Severity | Effort |
|---|---|---|---|
| 1 | Hard-drop double-input during animation | Medium | 5 min |
| 2 | `rotationIndex` should be `let` | Medium | 1 min |
| 3 | ConsoleGameUI semaphore in async context | Medium | 15 min |
| 4 | Tests don't exercise GameController | Medium | 30 min |
| 5 | ScoreStorage duplicate rejection | Low | 2 min |
| 6 | `removeClearedRows` complexity | Low | 5 min |
| 7 | Two `canMoveDown` overloads | Low | 2 min |
| 8 | `ConsoleUI` missing from products | Low | 1 min |
| 9 | README contradictions | Low | 5 min |
| 10 | Minor allocations, deprecated calls | Low | 5 min |

---

## 8. Conclusion

The project has a **strong architectural foundation** — clean layer separation, validated state machine, actor-based concurrency, and an efficient sparse grid. The SRS wall-kick implementation is correct. The public API (tick stream, `GameDisplayState`, `GameSettings`) is well-designed for consumer embedding.

The most actionable items are: (1) guard hard-drop input during animation, (2) lock `rotationIndex` as `let`, (3) migrate the game-over signal from `DispatchSemaphore` to async primitives, and (4) add integration tests that exercise `GameController` directly rather than mirrored helpers.
