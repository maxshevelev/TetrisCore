// TerminalAdapter.swift - Adapter pattern for terminal operations

import Foundation

public protocol TerminalOperations {
    var clear: String { get }
    var home: String { get }
    var eraseDown: String { get }
    var hideCursor: String { get }
    var showCursor: String { get }
    var reset: String { get }
    var bold: String { get }
    func getTerminalSize() -> (rows: Int, cols: Int)
    func cursorPosition(row: Int, col: Int) -> String
}

public struct TerminalAdapter: TerminalOperations {
    public func getTerminalSize() -> (rows: Int, cols: Int) {
        Terminal.getTerminalSize()
    }

    public func cursorPosition(row: Int, col: Int) -> String {
        Terminal.cursorPosition(row: row, col: col)
    }

    public var clear: String { Terminal.clear }
    public var home: String { Terminal.home }
    public var eraseDown: String { Terminal.eraseDown }
    public var hideCursor: String { Terminal.hideCursor }
    public var showCursor: String { Terminal.showCursor }
    public var reset: String { Terminal.reset }
    public var bold: String { Terminal.bold }

    public init() {}
}
