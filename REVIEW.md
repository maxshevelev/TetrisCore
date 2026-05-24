# TetrisCore — Full Project Review

**Date**: 2026-05-24
**Branch**: main
**Build**: Passing (0 warnings)
**Tests**: 19/19 passing

---

## 1. Architecture

The three-layer split (TetrisCore / ConsoleUI / tetris) is clean and well-justified. The actor-based `GameController` with diff-style `AsyncStream<Set<GameEvent>>` is a sound event-driven architecture. The validated `validTransitions` table centralizes state machine logic.

**Assessment**: Solid. The layer boundaries are strict and the public API surface is minimal.

---

## 2. Bugs

### 2.1 PersistentGameSettings notify() deadlocks (CRITICAL)

**File**: `GameSettings.swift:43-50`, `notify()` at line 92-99

```swift
// In playerName setter:
set {
    let trimmed = newValue.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    lock.withLock { _playerName = trimmed }  // outer lock
    persist()
    notify()  // <- called OUTSIDE the lock — but also inside (line 93)!
}

private func notify() {
    lock.withLock {                    // inner lock — same NSLock
        listeners.removeAll { $0.value == nil }
    }
    for w in listeners {
        w.value?.settingsDidUpdate(self)
    }
}
```

`notify()` acquires the same `NSLock` that is not reentrant. This will deadlock on any settings change that has listeners registered. Since `GameController` is the only consumer and the listener protocol has no default impl, this may never execute in practice — but the code is fundamentally broken.

**Fix**: Remove the `lock.withLock` from `notify()` (callers hold the lock), or use a separate dispatch queue for notification, or remove the listener pattern entirely if no consumers exist.

### 2.2 ScoreStorage race condition (HIGH)

**File**: `ScoreStorage.swift:35-43`

`loadScoresPrivate()` reads the file without holding the lock. Concurrent `add()` calls from different code paths could read stale files simultaneously, then both write — one score gets lost (classic lost-update).

**Fix**: Use a serial dispatch queue for all `ScoreStorage` access instead of `NSLock` with scattered unlocks.

### 2.3 Hard-drop movement not blocked outside animation (MEDIUM)

**File**: `GameController.swift:276-293`

```swift
private func moveLeft() {
    guard isPlaying, !isHardDropAnimating else { return }
```

`isHardDropAnimating` only blocks movement during the animation window. After the animation period, the drop timer's `pieceBlockedOnLastTick` path sets the flag to true and the drop tick will lock the piece — but `moveLeft`/`moveRight`/`rotatePiece` can still run during this gap because they check `isHardDropAnimating`, not `pieceBlockedOnLastTick`.

**Impact**: If the user sends input during the drop-catch-up period (after hard-drop animation delay), the piece moves around while simultaneously being locked by the timer. This produces inconsistent grid state.

---

## 3. Dead Code & Stale Artifacts

### 3.1 BlockState.swift is unused dead code

**File**: `Sources/TetrisCore/BlockState.swift`

The grid is stored as `[[BlockState]]` internally but only filled cells are populated. `BlockState.empty` cells are never written or read by game logic — only the sparse dictionary representation in `GameEvent.grid` uses `BlockState`. `BlockState` is never used by any game logic.

**Recommendation**: Delete `BlockState.swift`. The `GameEvent.grid` case still carries the `[[BlockState]]` type but is never consumed by the console renderer (which uses the sparse `grid` dictionary directly from accumulated state).

### 3.2 Tests duplicate internal helper functions

**File**: `Tests/TetrisCoreTests/GameControllerTests.swift`

Lines 285-305: `isColliding()`, `canMoveDown()` are re-implemented in the test file. These are internal to `GameController` and the copies can diverge from the actual implementation. The tests verify the test helpers, not the game engine.

### 3.3 TetrominoShape.blocks allocates on every access

**File**: `Tetromino.swift:20-61`

The `blocks` property is a computed property that returns a new 3D array each time. Since the shape definitions are immutable constants, this should be a `static let` with pre-computed rotation data.

### 3.4 allShapes array allocated on every call

**File**: `GameController.swift:113, 199, 400`

```swift
let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

Allocated fresh in `init()`, `resetGame()`, and `spawnNextPiece()`. Should be a private static constant.

---

## 4. Performance

### 4.1 Terminal size queried every render

**File**: `ConsoleRenderer.swift:18`

`terminal.getTerminalSize()` calls `ioctl` on every tick (~60fps). Terminal dimensions rarely change during gameplay.

**Fix**: Cache with `lazy` or `@TaskLocal`/`@Sendable` snapshot updated on SIGWINCH.

### 4.2 Grid format still dense

**File**: `GameEvent.swift:8`, `GameController.swift:54`, `BlockState.swift`

The internal grid is `[[BlockState]]` (200 cells). Every `render()` call copies the entire grid. The sparse dictionary approach (discussed on PR #11) would eliminate these copies.

---

## 5. UX & Design Issues

### 5.1 No game-over restart loop

**File**: `ConsoleGameUI.swift:68-73`

After game over, the UI waits on `doneSemaphore` for the user to press `q`. There is no loop that restarts the game. Traditional Tetris shows the score, then accepts space to play again.

### 5.2 Hard-coded grid dimensions

**File**: `ConsoleRenderer.swift:20-21`

`width = 10`, `height = 20` are hardcoded. These match the game logic constants but there is no synchronization — if the game grid size ever changes, the renderer silently misaligns.

### 5.3 Hard-coded controls in renderer

**File**: `ConsoleRenderer.swift:100-106`

Controls are a static string array embedded in the renderer. These should be data-driven or configurable so changing keybindings doesn't require editing the renderer.

---

## 6. Test Coverage

### 6.1 Missing critical paths

| Path | Status |
|------|--------|
| State machine transitions | Not tested |
| `GameSettings` listener notification | Not tested |
| ScoreStorage concurrency | Not tested |
| Game-over -> restart flow | Not tested |
| `ConsoleRenderer` output | Not tested |
| `ConsoleInputHandler` key mapping | Not tested |
| `isHardDropAnimated` behavior | Not tested |
| `isLineClearAnimated` behavior | Not tested |
| Score multipliers | Not tested |

### 6.2 Tests use stale internal types

The tests reference `[[BlockState]]` grid type which is the dense representation. Tests duplicate `isColliding()` and `canMoveDown()` — internal helpers that can diverge from the real implementation.

### 6.3 Tests don't exercise async actor behavior

All tests avoid `await` by testing pure logic in isolation. The actor's timing-dependent behavior (drop timer, lock delay, state transitions) is never tested.

---

## 7. Code Quality Notes

### 7.1 GameState is not public

**File**: `GameState.swift:1`

`enum GameState` is `Sendable` but not `public`. It's never exposed outside the module, so the `Sendable` conformance is unnecessary API surface.

### 7.2 render() called from multiple paths

`render()` is called from the drop timer task, the input listener, and `start()`. This means the tick stream can yield events from concurrent actor contexts if any path races. In practice the actor serializes access, but the call sites make it easy to miss a path.

### 7.3 ConsoleGameUI uses @unchecked Sendable

**File**: `ConsoleGameUI.swift:7`

`input` and `currentDisplayState` are accessed from both the async task (tick loop) and background thread (input handler) without synchronization.

---

## 8. Prioritized Recommendations

| # | Issue | Priority | Effort | Notes |
|---|---|---|---|---|
| 1 | PersistentGameSettings notify() deadlock | Critical | 5 min | Remove lock from notify() |
| 2 | ScoreStorage race | High | 10 min | Serial queue instead of NSLock |
| 3 | Hard-drop movement gap | Medium | 10 min | Also check pieceBlockedOnLastTick |
| 4 | Delete BlockState.swift | Medium | 2 min | Dead code |
| 5 | Tests duplicate helpers | Medium | 15 min | Use GameController API |
| 6 | Cache terminal size | Low | 2 min | |
| 7 | Static shapes constant | Low | 2 min | |
| 8 | Add game-over restart loop | Low | 10 min | UX improvement |
| 9 | Merge PR #11 (sparse grid) | Low | 5 min | |

---

## 9. Conclusion

The project has a **strong architectural foundation** — clean layer separation, validated state machine, actor-based concurrency, and event-driven design. The core game logic is well-implemented.

The most impactful fixes are:
1. **PersistentGameSettings notify()** — broken deadlock
2. **ScoreStorage thread safety** — race condition on concurrent access
3. **Hard-drop movement blocking** — gap in state protection

The sparse-grid PR (#11) addresses the grid performance optimization but has not been merged.
