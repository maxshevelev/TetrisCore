// GameSettings.swift - Runtime settings for GameController, persisted to settings.json

import Foundation

public protocol SettingsUpdateListener: AnyObject, Sendable {
    func settingsDidUpdate(_ settings: any GameSettings)
}

public protocol GameSettings: AnyObject, Sendable {
    var playerName: String { get set }
    var lockImmediatelyAfterHardDrop: Bool { get set }
    var isHardDropAnimated: Bool { get set }
    var isLineClearAnimated: Bool { get set }
    var initialLevel: Int { get set }
    func addListener(_ listener: SettingsUpdateListener)
    func removeListener(_ listener: SettingsUpdateListener)
}

public final class PersistentGameSettings: GameSettings, @unchecked Sendable {
    private let lock = NSLock()

    private var _playerName: String
    private var _lockImmediately: Bool
    private var _hardDropAnimated: Bool
    private var _lineClearAnimated: Bool
    private var _initialLevel: Int

    private var listeners: [Weak] = []

    public func addListener(_ listener: SettingsUpdateListener) {
        lock.withLock {
            listeners.removeAll { $0.value == nil }
            listeners.append(Weak(value: listener))
        }
    }

    public func removeListener(_ listener: SettingsUpdateListener) {
        lock.withLock {
            listeners.removeAll { $0.value == nil || $0.value === listener }
        }
    }

    public var playerName: String {
        get { lock.withLock { _playerName } }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            lock.withLock { _playerName = trimmed }
            persist()
            notify()
        }
    }

    public var lockImmediatelyAfterHardDrop: Bool {
        get { lock.withLock { _lockImmediately } }
        set {
            lock.withLock { _lockImmediately = newValue }
            persist()
            notify()
        }
    }

    public var isHardDropAnimated: Bool {
        get { lock.withLock { _hardDropAnimated } }
        set {
            lock.withLock { _hardDropAnimated = newValue }
            persist()
            notify()
        }
    }

    public var isLineClearAnimated: Bool {
        get { lock.withLock { _lineClearAnimated } }
        set {
            lock.withLock { _lineClearAnimated = newValue }
            persist()
            notify()
        }
    }

    public var initialLevel: Int {
        get { lock.withLock { _initialLevel } }
        set {
            lock.withLock { _initialLevel = min(10, max(1, newValue)) }
            persist()
            notify()
        }
    }

    // MARK: - Listeners

    private func notify() {
        lock.withLock {
            listeners.removeAll { $0.value == nil }
        }
        for w in listeners {
            w.value?.settingsDidUpdate(self)
        }
    }

    private struct Weak {
        weak var value: SettingsUpdateListener?
    }

    public init() {
        let stored = Self.loadSettings()
        self._playerName = stored.playerName
        self._lockImmediately = stored.lockImmediately
        self._hardDropAnimated = stored.hardDropAnimated
        self._lineClearAnimated = stored.lineClearAnimated
        self._initialLevel = stored.initialLevel
        persist()
    }

    // MARK: - Persistence

    private func persist() {
        let dict: [String: Any] = [
            "playerName": _playerName,
            "lockImmediatelyAfterHardDrop": _lockImmediately,
            "isHardDropAnimated": _hardDropAnimated,
            "isLineClearAnimated": _lineClearAnimated,
            "initialLevel": _initialLevel,
        ]
        do {
            try FileManager.default.createDirectory(
                at: Self.appSettingsPath.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
            try data.write(to: Self.appSettingsPath, options: .atomic)
        } catch {
            // Best-effort - silent fail
        }
    }

    private static func loadSettings() -> (playerName: String, lockImmediately: Bool, hardDropAnimated: Bool, lineClearAnimated: Bool, initialLevel: Int) {
        guard let data = try? Data(contentsOf: appSettingsPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return (NSUserName(), false, false, false, 1)
        }
        let name = (json["playerName"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? NSUserName()
        let lockImmediately = json["lockImmediatelyAfterHardDrop"] as? Bool ?? false
        let hardDropAnimated = json["isHardDropAnimated"] as? Bool ?? false
        let lineClearAnimated = json["isLineClearAnimated"] as? Bool ?? false
        let initialLevel = min(10, max(1, (json["initialLevel"] as? Int) ?? 1))
        return (name, lockImmediately, hardDropAnimated, lineClearAnimated, initialLevel)
    }

    private static var appSettingsPath: URL {
        tetrisDirectory().appendingPathComponent("settings.json")
    }

    private static func tetrisDirectory() -> URL {
    #if os(macOS)
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tetris")
    #else
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("Tetris")
    #endif
    }
}
