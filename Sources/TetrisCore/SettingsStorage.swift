// SettingsStorage.swift – Persistent top-scores and settings backed by JSON files

import Foundation

public struct StoredScore: Hashable, Codable, Equatable, Sendable {
    public let playerName: String
    public let score: Int

    public init(playerName: String = defaultPlayerName(), score: Int) {
        self.playerName = playerName
        self.score = score
    }
}

public final class SettingsStorage: Sendable {
    private let filePath: URL
    private let lock = NSLock()

    /// Creates a storage pointing to the given file URL.
    /// Defaults to `~/.tetris/scores.json` on macOS, `~/Library/Application Support/Tetris/scores.json` on iOS.
    public init(filePath: URL? = nil) {
        if let filePath {
            self.filePath = filePath
        } else {
            self.filePath = tetrisDirectory().appendingPathComponent("scores.json")
        }
    }

    /// Saves a new score then keeps only the top 10.
    @discardableResult
    public func add(score: Int, playerName: String = defaultPlayerName()) -> [StoredScore] {
        lock.lock()
        defer { lock.unlock() }
        let newEntry = StoredScore(playerName: playerName, score: score)
        guard !loadScoresPrivate().contains(where: { $0.score == score && $0.playerName == playerName }) else {
            return loadScoresPrivate()
        }
        var scores = loadScoresPrivate()
        scores.append(newEntry)
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
            // Best-effort persistence - silent fail
        }
    }
}

// MARK: - Player name storage

private func tetrisDirectory() -> URL {
#if os(macOS)
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tetris")
#else
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        .appendingPathComponent("Tetris")
#endif
}

private var appSettingsPath: URL {
    tetrisDirectory().appendingPathComponent("settings.json")
}

public func defaultPlayerName() -> String {
    if let data = try? Data(contentsOf: appSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let name = json["playerName"] as? String, !name.isEmpty {
        return name
    }
    return NSUserName()
}

public func storePlayerName(_ name: String) {
    var settings: [String: Any] = [:]
    if let data = try? Data(contentsOf: appSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        settings = json
    }
    settings["playerName"] = name
    do {
        try FileManager.default.createDirectory(
            at: appSettingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        try data.write(to: appSettingsPath, options: .atomic)
    } catch {
        // Best-effort - silent fail
    }
}

// MARK: - Hard-drop lock setting

public func lockImmediatelyAfterHardDrop() -> Bool {
    if let data = try? Data(contentsOf: appSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let value = json["lockImmediatelyAfterHardDrop"] as? Bool {
        return value
    }
    storeLockImmediatelyAfterHardDrop(false)
    return false
}

public func storeLockImmediatelyAfterHardDrop(_ value: Bool) {
    var settings: [String: Any] = [:]
    if let data = try? Data(contentsOf: appSettingsPath),
       let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        settings = json
    }
    settings["lockImmediatelyAfterHardDrop"] = value
    do {
        try FileManager.default.createDirectory(
            at: appSettingsPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: settings, options: [.sortedKeys])
        try data.write(to: appSettingsPath, options: .atomic)
    } catch {
        // Best-effort - silent fail
    }
}
