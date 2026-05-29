# TetrisCore — Full Project Review

**Date**: 2026-05-29
**Branch**: tetromino-immutable-rotationIndex
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
| **iOS paths use `fatalError`** | Medium | `PersistentGameSettings.tetrisDirectory()` uses `#else` to fall to `applicationSupportDirectory` — safe. But `ScoreStorage.tetrisDirectory()` at file scope (line 79 of ScoreStorage.swift) has no `#if os(macOS)` guard — the `#else` falls through the `tetrisDirectory()` function which itself is not `#if`-guarded. iOS will crash on `homeDirectoryForCurrentUser` if compiled for iOS target. |

---

## 2. Bugs & Correctness

### 2.1 `nextPiece` assigned twice in `init()` and `resetGame()` (GameController, lines 115–120)

```swift
// init(): line 116 assigns, then line 120 overwrites — first value lost
self.nextPiece = Tetromino(shape: shapes.randomElement()!)  // line 116 (lost)
self.currentPiece = self.nextPiece                           // line 117
self.currentX = width / 2 - 2                                // line 118
self.currentY = 0                                             // line 119
self.nextPiece = Tetromino(shape: shapes.randomElement()!)  // line 120 (actual next)
```

`nextPiece` is set at line 116, then immediately overwritten at line 120. Line 117 (`currentPiece = nextPiece`) assigns the *discarded* first random piece. The intended sequence is: pick a piece, assign it as current, then pick a new next.

**Same bug in `resetGame()` at lines 202 and 206.**

**Severity**: Low. Both values are random pieces anyway — the game works identically either way. But it's misleading and wastes a random draw per game.

**Fix**: Remove line 116 and line 202.

---

### 2.2 `hardDropPiece()` can set `pendingHardDropDuration` during animation (GameController, line 319)

`moveLeft()`, `moveRight()`, and `rotatePiece()` all guard `!isHardDropAnimating`. `hardDropPiece()` does not.

```swift
private func hardDropPiece() {
    guard isPlaying else { return }  // ← no !isHardDropAnimating
```

If two hard-drop events arrive while the animation is active (possible with fast input), the second invocation sets a new `pendingHardDropDuration` that leaks into the next tick.

**Severity**: Low. The `dropTimerGeneration` guard inside the animation task limits real damage. The leaked `pendingHardDropDuration` is cosmetic.

**Fix**: Add `!isHardDropAnimating` to the guard at line 319.

---

### 2.3 `hardDropPiece()` with `lockImmediatelyAfterHardDrop = false` leaves cancelled timer dangling (GameController, lines 339–342)

```swift
} else {
    pieceBlockedOnLastTick = true
    transition(to: .dropping)  // ← game back to dropping
}
// But dropTimer was cancelled at line 322!
```

The drop timer is cancelled at line 322. When `lockImmediatelyAfterHardDrop = false`, the animation task sets `pieceBlockedOnLastTick` and transitions to `.dropping`, but the timer is dead. The `dropping` state's `didSet` would call `resetDropTimer()` — *except* the state doesn't change (it was already `dropping` before the hard drop). No new timer is started.

The next drop timer *does* get reset in `render()` via the drop timer task completion... no, it doesn't. The drop timer is simply not reset.

Wait: re-examining. `isHardDropAnimating` is set to `settings.lockImmediatelyAfterHardDrop` which is `false`. So `isHardDropAnimating` stays `false`. But the timer was cancelled. And the state never changes (was `dropping`, stays `dropping`). The piece locks when `canMoveDown()` returns false on the next tick — but the drop timer is dead, so no tick fires.

Actually: the drop timer is the *only* mechanism that fires `render()` during play. Once cancelled, nothing calls `render()` or moves the piece until... something restarts the timer. The next user input does call `render()`, but that doesn't start the timer either.

**Severity**: Medium. After a hard drop with `lockImmediatelyAfterHardDrop = false` and `isHardDropAnimated = true`, the game freezes until the user presses any key (which restarts the timer via `startInputListener` → `render()` is called but still no timer restart). Actually, user input calls `render()` but not `resetDropTimer()`. The piece is stuck.

**Wait** — re-reading the code more carefully. The animation task at lines 329–344 runs on `dropTimer` (which was reassigned at line 328 with `dropTimerGeneration = gen`). The guard at line 331 (`dropTimerGeneration == gen`) passes because nothing changes generation. The animation task runs and sets `pieceBlockedOnLastTick = true`. But the timer is still dead.

The game loop continues because `render()` is called inside the animation task. But the *drop timer* (which drives the falling animation) is dead. The game freezes.

**Fix**: In the `else` branch (line 341), call `resetDropTimer()` to restart the drop timer.

---

### 2.4 `ScoreStorage.add()` deduplicates globally (ScoreStorage, line 35)

```swift
guard !loadScores().contains(where: { $0.score == score && $0.playerName == playerName }) else {
```

A player scoring exactly the same value in two different games gets the second score silently rejected. The deduplication is scoped to all-time history, not per-session.

**Severity**: Low. Exact-score collisions are rare. But the semantic intent is wrong — dedup should be scoped to the current game, not cross-game.

**Fix**: Remove the guard entirely, or add a `gameId` to `StoredScore`.

---

### 2.5 `removeClearedRows(_:)` is O(n × m) (GameController, line 424)

```swift
for entry in grid where !linesToClear.contains(entry.key.y) {
    let shift = linesToClear.filter { $0 > entry.key.y }.count
```

`linesToClear.filter` iterates the cleared rows array for every grid entry. With ~200 cells and 4 cleared rows = 800 iterations. Pre-compute a `Set<Int>` for O(1) membership.

**Severity**: Low. Unmeasurable at 200 cells. But unnecessary.

---

### 2.6 `canMoveDown(from:)` returns `false` for `y >= height` (GameController, line 376)

```swift
private func canMoveDown(from y: Int) -> Bool {
    guard let piece = currentPiece else { return false }
    for (x, py) in piece.getAbsoluteCoordinates(xOffset: currentX, yOffset: y + 1) {
        if x < 0 || x >= width || py >= height { return false }  // ← returns false instead of true
        if py >= 0 && grid[PieceCoordinate(x: x, y: py)] != nil { return false }
    }
    return true
}
```

When the piece is entirely below the grid (`y >= height`), `canMoveDown` returns `false` because `py >= height` is true. But the piece is already off the board — it can't move down because it's gone, not because it's blocked. The mutating `canMoveDown()` at line 357 has the same logic.

**Severity**: Low. `ghostPieceCoords` iterates upward with `canMoveDown(from:)`, so the piece is always on or above the board. No real-world impact.

**Fix**: Return `true` when `y >= height` (piece is off the board, "can move" down indefinitely).

---

### 2.7 Ghost piece not emitted after hard drop animation (GameController, line 500)

When `isHardDropAnimated = true` and `lockImmediatelyAfterHardDrop = false`, the hard drop tick (tick N) emits `.pieceBlocks` with `hardDropDuration` but the ghost piece coordinates are the *pre-lock* position (the piece hasn't locked yet). After the animation (tick N+1), the piece locks and the ghost appears on the next tick (tick N+2 after spawn). There is no tick where the ghost is emitted *with* the hard-drop hint — the ghost is emitted separately.

This is not a bug per se, but the ghost piece coordinate emission and the hard-drop hint are on different ticks, making it impossible for a consumer to correlate them cleanly.

**Severity**: Low. The ConsoleUI renderer handles it fine by accumulating state.

---

## 3. Concurrency

### 3.1 `ConsoleGameUI` and `ConsoleInputHandler` are `@unchecked Sendable`

Both classes are marked `@unchecked Sendable` with no actual synchronization for cross-thread reads. `currentDisplayState` in `ConsoleInputHandler` is written from the `inputQueue` thread and read from `processByte` which runs on the same queue — this is fine within the same queue. But `ConsoleGameUI.currentDisplayState` is written from `ConsoleGameUI`'s tick task (line 55: `input.currentDisplayState = ...`) and read from `ConsoleInputHandler.processByte` (line 80: `self.currentDisplayState == .gameOver`) on the `inputQueue`. These are the *same* queue, so the read is on the same thread as the write — actually fine.

The real concern is `ConsoleGameUI` itself: `tasks` array is accessed from `run()` and potentially from other callers. No lock protects it.

**Severity**: Low-Medium. Works in practice because the only cross-thread access is within the same `inputQueue`. But `@unchecked Sendable` is a lie under Swift 6.

**Fix**: Use a dedicated serial queue for all access to `currentDisplayState`, or make it `actor`-backed.

### 3.2 `PersistentGameSettings` is `@unchecked Sendable` (GameSettings, line 20)

Protected by `NSLock` — safe. `notify()` deliberately releases the lock before iterating listeners (deadlock avoidance) — well-documented and correct.

**Verdict**: OK as-is.

### 3.3 `tickContinuation` is force-unwrapped (GameController, line 110)

```swift
var tkc: AsyncStream<Set<GameEvent>>.Continuation!
let tks = AsyncStream<Set<GameEvent>> { tkc = $0 }
self.tickContinuation = tkc
```

If `AsyncStream` init calls the closure synchronously, `tkc` is set before the assignment. In practice `AsyncStream` always calls the closure before returning, so this is safe. But the `!` is unnecessary — use a regular variable with a safe default.

**Severity**: Low. Not a realistic risk with `AsyncStream` implementation.

---

## 4. Test Coverage

### 4.1 Tests verify mirrored helpers, not `GameController`

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

### 5.2 README API documentation is inconsistent with actual code

- `GameController` init parameters: README line 128–133 shows `Logger()` default, but the actual default is `Logger()` (subsystem: "com.maxik.tetris") — correct.
- `ControlEvent` enum: README line 224 lists all cases including `.start` — **correct now** (was missing in prior review).
- `GameDisplayState` doc: README line 294-298 matches actual enum — **correct**.

**Verdict**: README is current. No issues found.

### 5.3 README scoring table alignment (README line 395)

```
| Lines Cleared | Base Score |
|---------------|-----------|
```

The table header separators are misaligned. Minor formatting issue.

**Severity**: Cosmetic.

### 5.4 README `ScoreStorage` note is incomplete

README line 375 says "This behavior will be fixed in a future release" — this is a TODO marker in the documentation itself.

**Severity**: Low. Documentation debt.

---

## 6. Code Quality

### 6.1 `shapes` array allocated on every call (GameController, lines 115, 201, 432)

```swift
let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

Allocated in `init()`, `resetGame()`, and `spawnNextPiece()`. Should be `private static let allShapes`.

**Severity**: Low. Negligible performance impact. But should be static constant.

### 6.2 `TetrominoShape.blocks` allocates fresh arrays on every access (Tetromino, line 20)

```swift
var blocks: [[[Int]]] {
    switch self {
    case .I:
        return [
            [[0, 1], [1, 1], [2, 1], [3, 1]],  // ← new array every call
            ...
```

Shape data is compile-time constant. Returns fresh allocations on every access.

**Severity**: Low. Small arrays, short-lived, GC'd immediately. But wasteful.

### 6.3 Terminal size queried every render (ConsoleRenderer, line 18)

`terminal.getTerminalSize()` calls `ioctl(TIOCGWINSZ)` on every tick. Terminal dimensions are stable during gameplay. Cache and refresh on `SIGWINCH`.

**Severity**: Low-Medium. `ConsoleRenderer` is public and `getTerminalSize()` should NOT be called per-frame.

### ✅ 6.4 `GameState.description` visibility (GameState, line 7)

**Fixed**: Changed `public var description` → `var description`. `GameState` is internal; the description is only used for debug logging inside TetrisCore.

### ✅ 6.5 `ControlEvent` naming: `.start` for game-over restart (ControlEvent + ConsoleInputHandler)

**Fixed**: ConsoleInputHandler now maps Space → `.start` in game over state (line 69). The `hardDropPiece()` method also guards `guard isPlaying else { return }` to prevent any game-over restart from hardDrop. Only `.start` can restart the game.

**Verdict**: Fixed.

---

## 7. iOS Compatibility

### ✅ 7.1 ScoreStorage iOS path (ScoreStorage, line 80)

**Fixed**: Replaced file-scope `tetrisDirectory()` with `ScoreStorage` static property using explicit `#elseif os(iOS)` and safe `??` fallback for `applicationSupportDirectory`. No more force-unwrap `first!`.

**Verdict**: Fixed.

### ✅ 7.2 `ConsoleInputHandler` uses `Darwin` (ConsoleInputHandler, line 3)

`Darwin` is macOS/iOS compatible. `tcgetattr`, `tcsetattr`, `winsize`, `ioctl` are all available on iOS. But stdin raw mode won't work in a normal iOS app (no terminal). ConsoleUI is correctly documented as macOS-only.

**Verdict**: ConsoleUI is macOS-only (correct). TetrisCore iOS target is safe — ScoreStorage uses explicit `#elseif os(iOS)` with safe unwrapping.

---

## 8. Prioritized Findings

| # | Status | Issue | Severity | Effort |
|---|--------|-------|----------|--------|
| 1 | ⚠️ | `nextPiece` assigned twice in `init()`/`resetGame()` (wasted random draw) | Low | 1 min |
| 2 | ⚠️ | `hardDropPiece()` missing `!isHardDropAnimating` guard | Low | 1 min |
| 3 | ⚠️ | **Drop timer dead after hard drop with animation** (lockImmediatelyAfterHardDrop = false) | Medium | 2 min |
| 4 | ⚠️ | ScoreStorage dedup scope is global, not per-game | Low | 2 min |
| 5 | ⚠️ | `removeClearedRows` O(n × m) — should use Set | Low | 2 min |
| 6 | ⚠️ | Tests don't exercise `GameController` at all | Medium | 30 min |
| 7 | ⚠️ | `ConsoleGameUI` / `ConsoleInputHandler` `@unchecked Sendable` | Low-Medium | 10 min |
| 8 | ⚠️ | `shapes` array, `blocks` computed, terminal size — should be cached | Low | 5 min |
| 9 | ⚠️ | README scoring table alignment | Cosmetic | 1 min |
| 10 | ⚠️ | `canMoveDown(from:)` returns false for off-board positions | Low | 1 min |

---

## 9. Conclusion

The project has a **strong architectural foundation** — clean layer separation, validated state machine, actor-based concurrency, sparse grid, and correct SRS wall-kick. The public API (tick stream, `GameDisplayState`, `GameSettings`) is well-designed for consumer embedding.

**Most actionable items**:

1. **Fix drop timer dead after hard drop with animation** (§ 2.3) — causes game freeze
2. **Add integration tests that exercise `GameController` directly** (§ 4.1) — current tests verify mirrored helpers, not the engine
3. **Remove double `nextPiece` assignment** (§ 2.1) — removes misleading dead code
4. **Cache `shapes` array, `blocks`, and terminal size** (§ 8) — code quality improvements
5. **Fix `@unchecked Sendable` classes** (§ 3.1) — Swift 6 compliance
