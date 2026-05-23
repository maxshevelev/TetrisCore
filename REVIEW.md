# TetrisCore Code Review (Updated 2026-05-22)

## Executive Summary

**Overall Assessment**: Well-architected project with strong foundation. Core game logic is solid, but there are several bugs and improvements needed before production deployment.

**Build Status**: ✅ Passing  
**Test Status**: ✅ All 19 tests pass (with compiler warnings)  
**Maturity**: Production-ready core, needs bug fixes and feature completeness

---

## Architecture & Code Quality

### Strengths

| Aspect | Rating | Notes |
|--------|--------|-------|
| **Architecture** | Strong | Clean separation (TetrisCore/ConsoleUI), actor-based concurrency |
| **Type Safety** | Strong | Swift 6 strict concurrency, proper Sendable use |
| **Code Organization** | Strong | Modular, focused single-responsibility files |
| **Documentation** | Good | In-code comments, CLAUDE.md, README, TODO.txt |
| **Test Coverage** | Medium | 19 tests, no coverage reports, some test improvements needed |

### Critical Issues

#### 1. Hard Drop State Machine Bug (HIGH) - **UNFIXED**
**Location**: `GameController.swift:328-348`

```swift
public func hardDropPiece() {
    guard isPlaying else { return }
    let startY = currentY
    while canMoveDown() { currentY += 1 }
    stopDropTimer()
    if isHardDropAnimated, currentY != startY {
        // ... animation logic with timer
    } else {
        transition(to: .locking)  // ← No makeLockTimer() call!
    }
}
```

**Problem**: `hardDropPiece()` sets state to `.locking` but doesn't start the lock timer. If paused during this window, the piece never locks because `stopLockTimer()` is only called in `state.didSet` for non-locking states.

**Impact**: Piece becomes permanently stuck in `.locking` state until game over. The `resetLockTimer()` function exists but is never called from `hardDropPiece()`.

**Fix**: Call `resetLockTimer()` after hard drop, or inline the lock logic when `isHardDropAnimated` is false.

#### 2. Sendability Issues (HIGH)
**Location**: `ConsoleGameUI.swift:7`, `ConsoleRenderer.swift:10`

Both use `@unchecked Sendable` but aren't truly thread-safe:
- `ConsoleGameUI.input` captured by `@Sendable` closures without synchronization
- `ConsoleRenderer.terminal` captured similarly

**Status**: Works in practice (closures run on same actor context) but compiler can't verify. This is a known limitation of `@unchecked Sendable`.

#### 3. Arrow Key Support Missing (HIGH) - **UNFIXED**
**Location**: `ConsoleInputHandler.swift:56-80`

Only single characters are handled. Terminal arrow keys send escape sequences (e.g., `\u{1b}[A` for Up, 3 bytes). The handler processes the ESC byte (27) which triggers pause instead of the intended action.

```swift
case "\u{1b}":  // ESC key sends this first, triggers pause
    let event = currentDisplayState == .paused ? .resume : .pause
```

**Fix**: Add escape sequence parsing buffer to handle multi-byte sequences.

---

### Medium Priority

#### 4. Score Deduplication Logic (MEDIUM)
**Location**: `SettingsStorage.swift:37-39`

```swift
guard !loadScoresPrivate().contains(where: { 
    $0.score == score && $0.playerName == playerName && $0.level == level 
}) else {
    return loadScoresPrivate()
}
```

**Issue**: Deduplication requires exact match on all three fields. Edge case: same player gets same score at different levels (or same level with different scoring paths) - entries won't merge.

**Recommendation**: Consider whether deduplication should be based on `(playerName, score)` only, or add a timestamp component.

#### 5. Player Name Validation (MEDIUM)
**Location**: `SettingsStorage.swift:104-121`

```swift
public func storePlayerName(_ name: String) {
    // ... no validation
    settings["playerName"] = name
```

**Issue**: Accepts empty strings, whitespace-only names. The `defaultPlayerName()` checks for empty strings but `storePlayerName()` doesn't.

**Fix**:
```swift
guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
```

#### 6. Game Over Flow Exits App (MEDIUM) - **UNFIXED**
**Location**: `ConsoleGameUI.swift:42-70`

```swift
let doneSemaphore = DispatchSemaphore(value: 0)
input?.onExit = { doneSemaphore.signal() }
// ...
doneSemaphore.wait()
// After this, the app terminates
```

**Issue**: After game over, the app exits instead of offering restart. The `GameController.restart()` method exists but the UI never calls it. The `onExit` callback is triggered by `q` key, not by game over.

**Traditional Tetris Flow**: Game over → show score → press space → new game (restart loop).

**Fix**: Implement restart loop in UI:
```swift
repeat {
    await controller.start()
    await withUnsafeContinuation { ... semaphore.wait() ... }
} while controller.state != .gameOver  // Keep going until user quits
```

#### 7. Terminal Size Caching (MEDIUM)
**Location**: `ConsoleRenderer.swift:18`

```swift
public func render(data: RenderSnapshot) -> String {
    let size = terminal.getTerminalSize()  // Called every render
```

**Issue**: Terminal size rarely changes. Repeated `ioctl(STDOUT_FILENO, TIOCGWINSZ)` calls are unnecessary.

**Fix**: Cache with `lazy var` or update on SIGWINCH signal (if terminal resize detection is needed).

---

### Low Priority / Refactoring

#### 8. Performance: Linear Search per Cell
**Location**: `ConsoleRenderer.swift:58`, `ConsoleRenderer.swift:128`

```swift
if let block = pieceBlocks.first(where: { $0.x == x && $0.y == y })
```

**Issue**: For 200-cell grid (10×20), each cell does a linear search through 4 piece blocks = O(n×m×pieces). Not critical at this scale but poor algorithm.

**Fix**: Use a `Set` or 2D dictionary:
```swift
let pieceSet = Set(pieceBlocks.map { ($0.x, $0.y) })
if pieceSet.contains((x, y)) { ... }
```

#### 9. Static Shapes Constant
**Location**: `GameController.swift:122`, `GameController.swift:392`

```swift
let shapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

**Issue**: Array allocated on every call to `init()` and `spawnNextPiece()`. Small allocation but unnecessary.

**Fix**: Add static constant:
```swift
private static let allShapes: [TetrominoShape] = [.I, .O, .T, .S, .Z, .J, .L]
```

#### 10. GameState Sendable Conformance (LOW)
**Location**: `GameState.swift:1`

```swift
enum GameState: CustomStringConvertible, Sendable {
```

**Issue**: Already has `Sendable` conformance - this was previously listed as an issue but is now correct.

#### 11. Extract OverlayLine
**Location**: `ConsoleRenderer.swift:151-166`

```swift
enum Alignment { case leading, center, trailing }

struct OverlayLine {
    let text: String
    let alignment: Alignment
    let color: ColorPalette?
    let isBold: Bool
```

**Issue**: Nested inside `ConsoleRenderer` - not reusable outside this file. Minor issue for a console-only project.

#### 12. Split render() Method
**Location**: `ConsoleRenderer.swift:17-147`

**Issue**: 140-line method mixing layout calculation with output generation. Contains nested helper functions (`centerColumn`, `renderOverlay`, `renderGameOverOverlay`).

**Fix**: Split into dedicated methods:
- `renderGrid()`
- `renderScoreLine()`
- `renderStatusLine()`
- `renderNextPiece()`
- `renderControls()`
- `renderOverlay()`

---

## Test Quality Issues

While all 19 tests pass, there are compiler warnings:

1. `var` declarations that should be `let` in test functions (e.g., line 8, 25, 42)
2. Unused variable initializations

**Recommendation**: Run `swift test --sanitize=thread` to check for data races. The `GameController` is an `actor` so it should be thread-safe, but the test helpers use global functions that bypass the actor.

**Missing Test Coverage**:
- No tests for `ConsoleInputHandler` escape sequence parsing
- No tests for `ConsoleRenderer` rendering output
- No integration tests for full game flow
- No tests for `storePlayerName` validation

---

## Recommendations Priority Matrix

| Priority | Issue | Effort | Impact |
|------ ----|-- -----|--------|----- ---|
| **High** | Hard drop lock timer missing | 10 min | Game correctness |
| **High** | Arrow key escape sequence handling | 20 min | UX completeness |
| **High** | Game over → restart loop | 15 min | UX improvement |
| **Medium** | Player name validation | 2 min | Data quality |
| **Medium** | Cache terminal size | 2 min | Performance |
| **Medium** | Score deduplication check | 5 min | Edge cases |
| **Low** | Static shapes constant | 2 min | Minor perf |
| **Low** | Split render method | 20 min | Maintainability |
| **Low** | Set-based lookup | 5 min | Algorithm improvement |

---

## Implementation Plan

### Phase 1: Critical Bug Fixes (45 min total)
1. **Fix hard drop lock timer** (10 min)
   ```swift
   // In hardDropPiece():
   } else {
       resetLockTimer()  // Add this line
       transition(to: .locking)
   }
   ```

2. **Add arrow key support** (20 min)
   - Add escape sequence buffer in `processByte()`
   - Handle `\u{1b}[A` (up), `\u{1b}[B` (down), `\u{1b}[C` (right), `\u{1b}[D` (left)
   - Map to existing control events

3. **Implement restart loop** (15 min)
   - Change `ConsoleGameUI` to loop on game over
   - Call `controller.restart()` instead of exiting

### Phase 2: Medium Improvements (9 min total)
4. **Add player name validation** (2 min)
5. **Cache terminal size** (2 min)
6. **Review score deduplication** (5 min)

### Phase 3: Low Priority (27 min total)
7. **Static shapes constant** (2 min)
8. **Set-based lookup** (5 min)
9. **Refactor render method** (20 min)

### Phase 4: Testing
10. **Add input handler tests**
11. **Add renderer tests**
12. **Add integration tests**
13. **Fix test compiler warnings**

---

## Code Review Summary

### Files Reviewed

| File | Lines | Status | Notes |
|------|-------|--------|-------|
| `GameController.swift` | 452 | ✅ Good | Actor-based, state machine well-implemented |
| `ConsoleGameUI.swift` | 162 | ⚠️ Needs work | Sendable issues, no restart loop |
| `ConsoleInputHandler.swift` | 98 | ⚠️ Needs work | Missing escape sequences |
| `ConsoleRenderer.swift` | 250 | ⚠️ Needs work | Large render method, linear searches |
| `SettingsStorage.swift` | 122 | ✅ Good | Thread-safe, minor validation issue |
| `Tetromino.swift` | 85 | ✅ Good | Immutable, Sendable |
| `GameState.swift` | 18 | ✅ Good | Already has Sendable |
| `GameEvent.swift` | ~50 | ✅ Good | Diff-style events well-designed |
| `Tests/GameControllerTests.swift` | 306 | ⚠️ Needs work | Compiler warnings, missing tests |

### Test Statistics
- **Total Tests**: 19
- **Passing**: 19 (100%)
- **Compiler Warnings**: ~5 (var → let, unused initializations)
- **Coverage Areas**: Movement, rotation, hard drop, collision, spawn, line clearing
- **Missing**: Input handler, renderer, integration

---

## Conclusion

This is a **well-architected codebase** with:
- Proper separation of concerns (TetrisCore/ConsoleUI separation)
- Actor-based concurrency with strict safety
- Good use of Swift 6 features (Sendable, strict concurrency)
- Clean, readable code with good documentation

The main issues are:
1. **Bug**: Hard drop state machine incomplete (piece gets stuck)
2. **Bug**: Input handler missing escape sequences (arrow keys don't work)
3. **UX**: Game over exits instead of restarting

**Once these three issues are fixed, the project is ready for production use.**

The test suite is adequate but could be expanded. The codebase follows Swift best practices and would make an excellent educational example of actor-based concurrent programming and state machine design in Swift.
