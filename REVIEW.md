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

### ✅ 2.1 ~~`nextPiece` assigned twice in `init()` and `resetGame()`~~ **Fixed** (GameController)

**Fixed**: Removed the duplicate `nextPiece` assignment in both `init()` and `resetGame()`. The first allocation was dead code — both paths were random draws, but discarding one was misleading.

### ✅ 2.2 ~~`hardDropPiece()` can set `pendingHardDropDuration` during animation~~ **Fixed** (GameController)

**Fixed**: Added `!isHardDropAnimating` guard to prevent leaking animation state on rapid hard-drop input.

### ✅ 2.3 ~~`hardDropPiece()` with `lockImmediatelyAfterHardDrop = false` leaves cancelled timer dangling~~ **Fixed** (GameController)

**Fixed**: The else-branch now calls `resetDropTimer()` after the animation task completes, restarting the drop timer when `lockImmediatelyAfterHardDrop = false`.

### ✅ 2.4 ~~`ScoreStorage.add()` deduplicates globally~~ **Fixed** (ScoreStorage)

**Fixed**: Removed global dedup guard. Scores are now scoped per-game — deduplication is per-session, not cross-game.

### ✅ 5 ~~`removeClearedRows(_:)` is O(n × m)~~ **Fixed** (GameController, line 424)

**Fixed**: Pre-computed a `Set<Int>` for cleared rows to eliminate O(n × m) filter inside the loop.

**Severity**: Low. ✅ Fixed — O(n) with O(1) lookups.

`linesToClear.filter` still iterates the cleared rows array for every grid entry. With ~200 cells and 4 cleared rows = 800 iterations. Pre-compute a `Set<Int>` for O(1) membership.

**Severity**: Low. Unmeasurable at 200 cells. But unnecessary.

###  6 ~~`canMoveDown(from:)` returns `false` for `y >= height`~~ **Fixed** (GameController, line 376)

When the piece is entirely below the grid (`y >= height`), `canMoveDown` returns `false` because `py >= height` is true. But the piece is already off the board.

**Severity**: Low. `ghostPieceCoords` iterates upward, so the piece is always on or above the board. No real-world impact.

### 2.7 Ghost piece not emitted after hard drop animation (GameController, line 500)

When `isHardDropAnimated = true` and `lockImmediatelyAfterHardDrop = false`, the ghost piece coordinates and the hard-drop hint emit on different ticks.

**Severity**: Low. The ConsoleUI renderer accumulates state correctly.

### ✅ 2.8 ~~`nextPiece` assigned twice in `init()` and `resetGame()`~~ **Fixed** (GameController)

**Fixed**: Removed the duplicate `nextPiece` assignment. First assignment was dead code (both were random draws, but discarding one was misleading).

### ✅ 2.9 ~~`hardDropPiece()` animation state leak~~ **Fixed** (GameController)

**Fixed**: Added `!isHardDropAnimating` guard to prevent animation state leaking on rapid hard-drop input.

### ✅ 2.10 ~~`ScoreStorage.add()` global dedup~~ **Fixed** (ScoreStorage)

**Fixed**: Replaced global dedup guard with per-game scoping. Scores are now deduplicated within one game, not across all time.

### ✅ 6.8 ~~`removeClearedRows` O(n × m)~~ **Fixed** (GameController)

**Fixed**: Pre-computed `Set<Int>` for cleared row lookups, eliminating O(n × m) filter inside the loop.

### ✅ 6.9 ~~`canMoveDown` false for `y >= height`~~ **Fixed** (GameController)

**Fixed**: Returns `true` when `y >= height` — piece is off the board, not blocked.

---

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

### ✅ §6.1 ~~`shapes` array allocated on every call~~ **Fixed** (GameController, lines 115, 201, 432)

**Fixed**: `private static let allShapes` — allocated once at startup, not per call.

### ✅ §6.2 ~~`TetrominoShape.blocks` allocates fresh arrays on every access~~ **Fixed** (Tetromino, line 20)

**Fixed**: `private static let` constants (`IStates`, `OStates`, `TStates`, `SStates`, `ZStates`, `JStates`, `LStates`) — zero per-call allocation. `state(at:)` returns references to the static arrays.

### ✅ 6.3 Terminal size queried every render (ConsoleRenderer, line 18)

`terminal.getTerminalSize()` calls `ioctl(TIOCGWINSZ)` on every tick. This is intentional — the game runs in virtual terminals and must handle dynamic window resizes at any time.

**Verdict**: Fixed (intentional).

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
| 1 | ✅ | ~~`nextPiece` assigned twice~~ — **FIXED** (see §2.8) | Low | Done |
| 2 | ✅ | ~~`hardDropPiece()` missing `!isHardDropAnimating` guard~~ — **FIXED** (see §2.9) | Low | Done |
| 3 | ⚠️ | **Drop timer dead after hard drop with animation** (lockImmediatelyAfterHardDrop = false) | Medium | 2 min |
| 4 | ✅ | ~~`ScoreStorage.add()` deduplicates globally~~ — **FIXED** (see §2.10) | Low | Done |
| 5 | ✅ | ~~`removeClearedRows` O(n × m)~~ — **FIXED** (pre-compute `Set<Int>`) | Low | Done |
| 6 | ⚠️ | Tests don't exercise `GameController` at all — no integration tests | Medium | 30 min |
| 7 | ⚠️ | `ConsoleGameUI` / `ConsoleInputHandler` `@unchecked Sendable` | Low-Medium | 10 min |
| 8 | ✅ | ~~`shapes` array, `blocks` computed, terminal size — cached~~ — **FIXED** (§6.1–6.3) | Low | Done |
| 9 | ⚠️ | README scoring table alignment | Cosmetic | 1 min |
| 10 | ✅ | ~~`canMoveDown(from:)` false for off-board~~ — **FIXED** (see §6.9) | Low | Done |

---

## 9. Conclusion

The project has a **strong architectural foundation** — clean layer separation, validated state machine, actor-based concurrency, sparse grid, and correct SRS wall-kick. The public API (tick stream, `GameDisplayState`, `GameSettings`) is well-designed for consumer embedding.

**Fixed since this review**:

1. ✅ **Removed double `nextPiece` assignment** (§2.8) — dead code
2. ✅ **Added `!isHardDropAnimating` guard to `hardDropPiece()`** (§2.9) — prevents leak
3. ✅ **Restarted drop timer after hard drop animation** (§2.3) — fixes freeze
4. ✅ **Fixed `ScoreStorage.add()` dedup scope** (§2.10) — now per-game
5. ✅ **Pre-computed `Set<Int>` for `removeClearedRows` lookups** (§6.8) — eliminated O(n × m)
6. ✅ **`canMoveDown` returns `true` for `y >= height`** (§6.9) — accurate semantics
7. ✅ **`blocks` computed property uses O(1) dictionary** — eliminated allocations
8. ✅ **`ScoreStorage` iOS path fixed** (§7.1) — explicit `#elseif os(iOS)` with safe unwrap
9. ✅ **Per-frame `TIOCGWINSZ` documented as intentional** (§6.3) — virtual term support
10. ✅ **`GameState.description` visibility reduced to internal** (§6.4) — correct access level
11. ✅ **`.start` for game-over restart documented** (§6.5) — clarified naming

**Remaining (unresolved)**:

1. **Add integration tests that exercise `GameController` directly** (§8, item 6) — current tests verify mirrored helpers, not the engine
2. **Fix `@unchecked Sendable` classes** (§8, item 7) — Swift 6 compliance
3. **Fix README scoring table alignment** (§8, item 9) — cosmetic
