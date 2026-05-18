// GameLogger.swift - Simple sendable logger for debug output
// Logging is off by default; use -d <file> to enable.

import Foundation

/// A sendable logging closure. Use `{ _ in }` for a no-op (default, logging off).
public final class GameLogger: @unchecked Sendable {
    private let log: @Sendable (String) -> Void

    /// Creates an active logger.
    public init(_ log: @escaping @Sendable (String) -> Void) {
        self.log = log
    }

    /// Creates a no-op logger (default when debug is off).
    public convenience init() {
        self.init { _ in }
    }

    public func log(_ message: String) {
        log(message)
    }
}
