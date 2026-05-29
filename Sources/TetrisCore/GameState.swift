enum GameState: CustomStringConvertible, Sendable {
    case initializing
    case dropping
    case paused
    case gameOver

    var description: String {
        switch self {
        case .initializing: return "initializing"
        case .dropping: return "dropping"
        case .paused: return "paused"
        case .gameOver: return "gameOver"
        }
    }
}
