// GameDisplayState.swift - Consumer-facing game state
// Internal timer states (dropping, locking, initializing) are collapsed
// so consumers only see what matters for their UI.

public enum GameDisplayState: Sendable {
    /// Game is actively running — render the board and accept input.
    case playing
    /// Game is paused — show a pause overlay.
    case paused
    /// Game is over — show game over screen with score.
    case gameOver
}
