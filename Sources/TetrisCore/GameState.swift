enum GameState: CustomStringConvertible, Sendable, Hashable {
    case initializing(width: Int, height: Int)
    case dropping
    case paused
    case gameOver

    /// Raw state without associated values — used for transition table lookups.
    enum RawState: Hashable {
        case initializing, dropping, paused, gameOver
    }

    var rawState: RawState {
        switch self {
        case .initializing: return .initializing
        case .dropping: return .dropping
        case .paused: return .paused
        case .gameOver: return .gameOver
        }
    }

    public var description: String {
        switch self {
        case .initializing: return "initializing"
        case .dropping: return "dropping"
        case .paused: return "paused"
        case .gameOver: return "gameOver"
        }
    }
}
