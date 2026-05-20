enum GameState: CustomStringConvertible, Sendable {
    case initializing
    case dropping
    case locking
    case paused
    case gameOver

    public var description: String {
        switch self {
        case .initializing: return "initializing"
        case .dropping: return "dropping"
        case .locking: return "locking"
        case .paused: return "paused"
        case .gameOver: return "gameOver"
        }
    }
}
