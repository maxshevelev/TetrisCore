// InputReceiver.swift - Protocol for receiving input events

public protocol InputReceiver: AnyObject & Sendable {
    func enqueue(_ event: KeyEvent) async
}
