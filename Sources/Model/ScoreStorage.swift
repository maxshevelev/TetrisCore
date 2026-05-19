// ScoreStorage.swift – Persistent top-scores backed by a JSON file

import Foundation

public struct StoredScore: Codable, Equatable {
    public let score: Int
    public let level: Int
    public let date: String

    public init(score: Int, level: Int, date: String = ISO8601DateFormatter().string(from: Date())) {
        self.score = score
        self.level = level
        self.date = date
    }
}

public final class ScoreStorage: Sendable {
    private let filePath: URL
    private let lock = NSLock()

    /// Creates a storage pointing to the given file URL.
    /// Defaults to `~/.tetris/scores.json`.
    public init(filePath: URL? = nil) {
        if let filePath {
            self.filePath = filePath
        } else {
            let dir = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".tetris")
            self.filePath = dir.appendingPathComponent("scores.json")
        }
    }

    /// Saves a new score then keeps only the top 10.
    @discardableResult
    public func add(score: Int, level: Int) -> [StoredScore] {
        lock.lock()
        defer { lock.unlock() }
        var scores = loadScoresPrivate()
        scores.append(StoredScore(score: score, level: level))
        scores.sort { $0.score > $1.score }
        scores = Array(scores.prefix(10))
        saveScoresPrivate(scores)
        return scores
    }

    public func topScores() -> [StoredScore] {
        lock.lock()
        defer { lock.unlock() }
        return loadScoresPrivate()
    }

    // MARK: - Private (unlocked callers)

    private func loadScoresPrivate() -> [StoredScore] {
        guard
            let data = try? Data(contentsOf: filePath),
            let scores = try? JSONDecoder().decode([StoredScore].self, from: data)
        else {
            return []
        }
        return scores
    }

    private func saveScoresPrivate(_ scores: [StoredScore]) {
        do {
            try FileManager.default.createDirectory(
                at: filePath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(scores)
            try data.write(to: filePath, options: .atomic)
        } catch {
            // Best-effort persistence – silent fail
        }
    }
}
