// ScoreStorage.swift – Persistent top-scores backed by a JSON file

import Foundation

public protocol ScoreStorageProtocol: Sendable {
    func add(score: Int, playerName: String) -> [StoredScore]
    func topScores() -> [StoredScore]
}

public struct StoredScore: Hashable, Codable, Equatable, Sendable {
    public let playerName: String
    public let score: Int

    public init(playerName: String = "", score: Int) {
        self.playerName = playerName
        self.score = score
    }
}

public final class ScoreStorage: Sendable, ScoreStorageProtocol {
    private let filePath: URL
    private let queue = DispatchQueue(label: "tetris.scorestorage", qos: .userInitiated)

    /// Creates a storage pointing to the given file URL.
    /// Defaults to `~/.tetris/scores.json` on macOS, `~/Library/Application Support/Tetris/scores.json` on iOS.
    public init(filePath: URL? = nil) {
        if let filePath {
            self.filePath = filePath
        } else {
            self.filePath = Self.defaultScoresPath
        }
    }

    /// Saves a new score then keeps only the top 10.
    @discardableResult
    public func add(score: Int, playerName: String) -> [StoredScore] {
        var result: [StoredScore]!
        queue.sync {
            let newEntry = StoredScore(playerName: playerName, score: score)
            guard !loadScores().contains(where: { $0.score == score && $0.playerName == playerName }) else {
                result = loadScores()
                return
            }
            var scores = loadScores()
            scores.append(newEntry)
            scores.sort { $0.score > $1.score }
            scores = Array(scores.prefix(10))
            saveScores(scores)
            result = scores
        }
        return result
    }

    public func topScores() -> [StoredScore] {
        queue.sync { loadScores() }
    }

    // MARK: - Private (queue-executed callers only)

    private func loadScores() -> [StoredScore] {
        guard
            let data = try? Data(contentsOf: filePath),
            let scores = try? JSONDecoder().decode([StoredScore].self, from: data)
        else {
            return []
        }
        return scores
    }

    private func saveScores(_ scores: [StoredScore]) {
        do {
            try FileManager.default.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(scores)
            try data.write(to: filePath, options: .atomic)
        } catch {
            // Best-effort persistence - silent fail
        }
    }
}

private extension ScoreStorage {
    static var defaultScoresPath: URL {
#if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tetris")
            .appendingPathComponent("scores.json")
#elseif os(iOS)
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first 
            .map { $0.appendingPathComponent("Tetris").appendingPathComponent("scores.json") }
            ?? .applicationDirectory.deletingLastPathComponent()
                .appendingPathComponent("scores.json")
#else
        FileManager.default.currentDirectoryPath
            .appendingPathComponent(".tetris")
            .appendingPathComponent("scores.json")
#endif
    }
}
